require 'spec_helper'

ENV['APP_ENV'] = 'test'

RSpec.describe 'Web UI' do
  include Rack::Test::Methods

  def app
    Rollout::UI::Web
  end

  it "renders index html" do
    get '/'

    expect(last_response).to be_ok
    expect(last_response.body).to include('Rollout UI')
  end

  it "renders index json" do
    ROLLOUT.activate(:fake_test_feature_for_rollout_ui_webspec)
    header 'Accept', 'application/json'

    get '/'

    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expected_response = {
      "data"=>{},
      "groups"=>[],
      "name"=>"fake_test_feature_for_rollout_ui_webspec",
      "percentage"=>100.0,
      "users"=>""
    }
    expect(response).to include(expected_response)
    ROLLOUT.delete(:fake_test_feature_for_rollout_ui_webspec)
  end

  it "renders index json filtered by user and group" do
    ROLLOUT.deactivate(:fake_test_feature_for_rollout_ui_webspec)
    ROLLOUT.activate_user(:fake_test_feature_for_rollout_ui_webspec, 'fake_user')
    ROLLOUT.activate_group(:fake_test_feature_for_rollout_ui_webspec, :fake_group)

    header 'Accept', 'application/json'
    get '/?user=different_user'
    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expect(response).to be_empty

    expected_feature = {
      "data" => {},
      "groups" => ["fake_group"],
      "name" => "fake_test_feature_for_rollout_ui_webspec",
      "percentage" => 0.0,
      "users" => "fake_user"
    }
    header 'Accept', 'application/json'
    get '/?user=fake_user'
    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expect(response).to include(expected_feature)

    header 'Accept', 'application/json'
    get '/?group=fake_group'
    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expect(response).to include(expected_feature)

    ROLLOUT.deactivate_user(:fake_test_feature_for_rollout_ui_webspec, 'fake_user')
    ROLLOUT.deactivate_group(:fake_test_feature_for_rollout_ui_webspec, :fake_group)
    ROLLOUT.delete(:fake_test_feature_for_rollout_ui_webspec)
  end

  it "rescapes javascript in the action index" do
    ROLLOUT.activate(:'+alert(1)+')

    get '/'

    expect(last_response).to be_ok
    expect(last_response.body).to include('Rollout UI') & include("&amp;#x27;+alert(1)+&amp;#x27;")
  end

  it "exports all the features as json" do
    ROLLOUT.activate(:fake_test_feature_for_rollout_ui_webspec)
    ROLLOUT.activate(:fake_test_feature_for_rollout_ui_webspec_2)
    header 'Accept', 'application/json'

    get '/export.json'

    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    first_feature = {
      "data"=>{},
      "groups"=>[],
      "name"=>"fake_test_feature_for_rollout_ui_webspec",
      "percentage"=>100.0,
      "users"=>""
    }
    second_feature = {
      "data"=>{},
      "groups"=>[],
      "name"=>"fake_test_feature_for_rollout_ui_webspec_2",
      "percentage"=>100.0,
      "users"=>""
    }
    expect(response).to include(first_feature, second_feature)
    ROLLOUT.delete(:fake_test_feature_for_rollout_ui_webspec)
    ROLLOUT.delete(:fake_test_feature_for_rollout_ui_webspec_2)
  end

  it "renders the import page" do
    get "/import"

    expect(last_response).to be_ok
    expect(last_response.body)
      .to include("Warning: Importing this file will replace any existing features with the same name.")
  end

  it "imports features from a json file" do
    ROLLOUT.with_feature(:old_feature) do |feature|
      feature.percentage = 49.5
      feature.groups = [:old_group]
      feature.users = ["old_user"]
      feature.data.update(description: "old description")
      feature.data.update(updated_at: 1_703_948_574)
    end
    
    ROLLOUT.with_feature(:overridden_feature) do |feature|
      feature.percentage = 27.0
      feature.groups = [:old_overriden_group]
      feature.users = ["old_overriden_user"]
      feature.data.update(description: "old description")
      feature.data.update(updated_at: 1_703_948_000)
    end

    fixture_path = File.expand_path("../fixtures/features.json", __dir__)
    post "/import", features: Rack::Test::UploadedFile.new(fixture_path, "application/json")

    expect(ROLLOUT.get(:old_feature).to_hash).to eq(
      {
        data: {
          "description" => "old description",
          "updated_at" => 1_703_948_574
        },
        groups: [:old_group],
        percentage: 49.5,
        users: ["old_user"]
      }
    )
    expect(ROLLOUT.get(:new_feature).to_hash).to match(
      {
        data: {
          "description" => "New Feature",
          "updated_at" => a_kind_of(Integer)
        },
        groups: [:new_group],
        percentage: 12.0,
        users: ["first_new_user", "second_new_user"]
      }
    )
    expect(ROLLOUT.get(:overridden_feature).to_hash).to match(
      {
        data: {
          "description" => "New overridden Feature description",
          "updated_at" => a_kind_of(Integer)
      },
        groups: [:new_overriden_group],
        percentage: 100.0,
        users: ["new_overriden_user"]
    })

    ROLLOUT.delete(:old_feature)
    ROLLOUT.delete(:new_feature)
    ROLLOUT.delete(:overridden_feature)
  end

  it 'renders show html' do
    get '/features/test'

    expect(last_response).to be_ok
    expect(last_response.body).to include('Rollout UI') & include('test')
  end

  it "escapes javascript in the action show" do
    get "/features/'+alert(1)+'"

    expect(last_response).to be_ok
    expect(last_response.body).to include('Rollout UI') & include("&amp;#x27;+alert(1)+&amp;#x27;")
  end

  it "renders show json" do
    ROLLOUT.activate(:fake_test_feature_for_rollout_ui_webspec)
    header 'Accept', 'application/json'

    get '/features/fake_test_feature_for_rollout_ui_webspec'

    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expected_response = {
      "data"=>{},
      "groups"=>[],
      "name"=>"fake_test_feature_for_rollout_ui_webspec",
      "percentage"=>100.0,
      "users"=>""
    }
    expect(expected_response).to eq response

    ROLLOUT.delete(:fake_test_feature_for_rollout_ui_webspec)
  end
end
