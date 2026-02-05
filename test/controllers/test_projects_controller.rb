require 'json-schema'

class TestProjectsController < TestCase

  DEBUG_MESSAGES=false

  # JSON Schema
  # This could be in the Project model, see
  # https://github.com/ncbo/ontologies_linked_data/issues/22
  # json-schema for description and validation of REST json responses.
  # http://tools.ietf.org/id/draft-zyp-json-schema-03.html
  # http://tools.ietf.org/html/draft-zyp-json-schema-03
  JSON_SCHEMA_STR = <<-END_JSON_SCHEMA_STR
  {
    "type":"object",
    "title":"Project",
    "description":"A BioPortal project, which may refer to multiple ontologies.",
    "additionalProperties":true,
    "properties":{
      "@id":{ "type":"string", "format":"uri", "required": true },
      "@type":{ "type":"string", "format":"uri", "required": true },
      "acronym":{ "type":"string", "required": true },
      "name":{ "type":"string", "required": true },
      "creator":{ "type":"array", "required": true },
      "created":{ "type":"string", "format":"datetime", "required": true },
      "homePage":{ "type":"string", "format":"uri", "required": true },
      "description":{ "type":"string", "required": true },
      "institution":{ "type":"string" },
      "ontologyUsed":{ "type":"array", "items":{ "type":"string" } }
    }
  }
  END_JSON_SCHEMA_STR

  # Clear the triple store models
  def teardown
    delete_goo_models(LinkedData::Models::Project.all)
    delete_goo_models(LinkedData::Models::Ontology.all)
    delete_goo_models(LinkedData::Models::User.all)
    @projectParams = nil
    @user = nil
    @ont = nil
    @p = nil
  end

  def setup
    super
    teardown
    @user = LinkedData::Models::User.new(username: "test_user", email: "test_user@example.org", password: "password")
    @user.save
    @ont = LinkedData::Models::Ontology.new(acronym: "TST", name: "TEST ONTOLOGY", administeredBy: [@user])
    @ont.save
    @p = LinkedData::Models::Project.new
    @p.creator = [@user]
    @p.created = DateTime.now
    @p.name = "Test Project" # must be a valid URI
    @p.acronym = "TP"
    @p.homePage = RDF::IRI.new("http://www.example.org")
    @p.description = "A test project"
    @p.institution = "A university"
    @p.ontologyUsed = [@ont]
    @p.save
    @projectParams = {
        acronym: @p.acronym,
        name: @p.name,
        description: @p.description,
        homePage: @p.homePage.to_s,
        creator: @p.creator.map {|u| u.username},
        created: @p.created,
        institution: @p.institution,
        ontologyUsed: [@p.ontologyUsed.first.acronym]
    }
  end

  def test_all_projects
    get '/projects'
    _response_status(200, last_response)
    projects = MultiJson.load(last_response.body)
    assert_instance_of(Array, projects)
    assert_equal(1, projects.length)
    p = projects[0]
    assert_equal(@p.name, p['name'])
    validate_json(last_response.body, JSON_SCHEMA_STR, true)
  end

  def test_project_create_success
    # Ensure it doesn't exist first (undo the setup @p.save creation)
    _project_delete(@p.acronym)
    put "/projects/#{@p.acronym}", MultiJson.dump(@projectParams), "CONTENT_TYPE" => "application/json"
    _response_status(201, last_response)
    _project_get_success(@p.acronym, true)
    delete "/projects/#{@p.acronym}"
    post "/projects", MultiJson.dump(@projectParams.merge(acronym: @p.acronym)), "CONTENT_TYPE" => "application/json"
    assert last_response.status == 201
  end

  def test_project_create_conflict
    # Fail PUT for any project that already exists.
    put "/projects/#{@p.acronym}", MultiJson.dump(@projectParams), "CONTENT_TYPE" => "application/json"
    _response_status(409, last_response)
    # The existing project should remain valid
    _project_get_success(@p.acronym, true)
  end

  def test_project_create_failure
    # Ensure the project doesn't exist.
    _project_delete(@p.acronym)
    # Fail PUT for any project with required missing data.
    username = 'user_does_not_exist'
    @projectParams[:creator] = username
    put "/projects/#{@p.acronym}", MultiJson.dump(@projectParams), "CONTENT_TYPE" => "application/json"
    _response_status(422, last_response)
    _project_get_failure(@p.acronym)
  end

  def test_project_update_success
    patch "/projects/#{@p.acronym}", MultiJson.dump(@projectParams), "CONTENT_TYPE" => "application/json"
    _response_status(204, last_response)
    _project_get_success(@p.acronym)
    # TODO: validate the data updated
    #_project_get_success(@p.acronym, true)
  end

  def test_project_creator_multiple
    u1 = LinkedData::Models::User.new(username: 'Test User 1', email: 'user1@example.org', password: 'password')
    u1.save
    assert u1.valid?, u1.errors

    u2 = LinkedData::Models::User.new(username: 'Test User 2', email: 'user2@example.org', password: 'password')
    u2.save
    assert u2.valid?, u2.errors

    params = { name: @p.name, acronym: 'TSTPRJ', creator: [u1.username, u2.username], 
               description: 'Description of TSTPRJ', homePage: @p.homePage.to_s }
    put "/projects/#{params[:acronym]}", MultiJson.dump(params), "CONTENT_TYPE" => "application/json"
    assert_equal 201, last_response.status, last_response.body

    get "/projects/#{params[:acronym]}"
    assert last_response.ok?
    body = MultiJson.load(last_response.body)
    assert_equal(2, body['creator'].count)

    body['creator'].sort! { |a,b| a <=> b }
    assert_equal(u1.id.to_s, body['creator'].first)
    assert_equal(u2.id.to_s, body['creator'].last)
  end

  def test_project_delete
    _project_delete(@p.acronym)
    _project_get_failure(@p.acronym)
  end

  def _response_status(status, response)
    if DEBUG_MESSAGES
      assert_equal(status, response.status, response.body)
    else
      assert_equal(status, response.status)
    end
  end

  # Issues DELETE for a project acronym, tests for a 204 response.
  # @param [String] acronym project acronym
  def _project_delete(acronym)
    delete "/projects/#{acronym}"
    _response_status(204, last_response)
  end

  # Issues GET for a project acronym, tests for a 200 response, with optional response validation.
  # @param [String] acronym project acronym
  # @param [boolean] validate_data verify response body json content
  def _project_get_success(acronym, validate_data=false)
    get "/projects/#{acronym}"
    _response_status(200, last_response)
    if validate_data
      # Assume we have JSON data in the response body.
      p = MultiJson.load(last_response.body)
      assert_instance_of(Hash, p)
      assert_equal(acronym, p['acronym'], p.to_s)
      validate_json(last_response.body, JSON_SCHEMA_STR)
    end
  end

  # Issues GET for a project acronym, tests for a 404 response.
  # @param [String] acronym project acronym
  def _project_get_failure(acronym)
    get "/projects/#{acronym}"
    _response_status(404, last_response)
  end

end
