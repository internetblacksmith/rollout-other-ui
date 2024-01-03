require "sinatra"
require "sinatra/json"
require "rollout"

require "rollout/ui/version"
require "rollout/ui/config"
require "rollout/ui/helpers"

module Rollout::UI
  class Web < Sinatra::Base
    set :static, true
    set :public_folder, File.dirname(__FILE__) + '/public'

    helpers Helpers

    get '/' do
      @rollout = config.get(:instance)
      @features = @rollout.features.sort_by(&:downcase)
      if json_request?
        json(
          filtered_features(@rollout, @features).map do |feature|
            feature_to_hash(@rollout.get(feature))
          end
        )
      else
        slim :'features/index'
      end
    end

    get '/export.json' do
      rollout = config.get(:instance)
      features = rollout.features.sort_by(&:downcase)
      content_type 'application/json'
      attachment "all_features_#{Time.now.to_i}.json"
      json(features.map { |feature| feature_to_hash(rollout.get(feature)) })
    end

    get "/import" do
      slim :'features/import'
    end

    post "/import" do
      file = params.fetch("features", {}).fetch("tempfile", nil)
      redirect to("#{back}?error=Missing file") unless file
      begin
        features = JSON.parse(file.read, symbolize_names: true)
      rescue JSON::ParserError
        redirect to("#{back}?error=Invalid JSON file")
      end

      redirect to("#{back}?error=No features found") unless features.is_a?(Array)

      rollout = config.get(:instance)
      actor = config.get(:actor, scope: self)

      with_rollout_context(rollout, actor:) do
        features.each do |feature|
          upsert_feature(rollout, feature)
        end
      end

      redirect index_path
    end

    get '/features/new' do
      slim :'features/new'
    end

    post '/features/new' do
      redirect feature_path(params[:name])
    end

    get '/features/:feature_name' do
      @rollout = config.get(:instance)
      @feature = @rollout.get(params[:feature_name])

      if json_request?
        json(feature_to_hash(@feature))
      else
        slim :'features/show'
      end
    end

    post '/features/:feature_name' do
      rollout = config.get(:instance)
      actor = config.get(:actor, scope: self)
      feature_data = rollout.get(params[:feature_name]).data
      if feature_data['updated_at'] && params[:last_updated_at].to_s != feature_data['updated_at'].to_s
        redirect "#{feature_path(params[:feature_name])}?error=Rollout version outdated. Review changes below and try again."
      end
      with_rollout_context(rollout, actor:) do
        upsert_feature(rollout, params)
      end

      redirect feature_path(params[:feature_name])
    end

    post '/features/:feature_name/activate-percentage' do
      rollout = config.get(:instance)
      actor = config.get(:actor, scope: self)

      with_rollout_context(rollout, actor: actor) do
        rollout.with_feature(params[:feature_name]) do |feature|
          feature.percentage = params[:percentage].to_f.clamp(0.0, 100.0)
          feature.data.update(updated_at: Time.now.to_i)
        end
      end

      redirect index_path
    end

    post '/features/:feature_name/delete' do
      @rollout = config.get(:instance)
      @rollout.delete(params[:feature_name])

      redirect index_path
    end
  end
end
