class MappingsController < ApplicationController

  # Get mappings for a class
  get '/ontologies/:ontology/classes/:cls/mappings' do
    ontology = ontology_from_acronym(@params[:ontology])
    submission = ontology.latest_submission
    cls_id = @params[:cls]
    cls = LinkedData::Models::Class.find(RDF::URI.new(cls_id)).in(submission).first
    if cls.nil?
      reply 404, "Class with id `#{class_id}` not found in ontology `#{acronym}`" 
    end

    mappings = LinkedData::Mappings.mappings_ontology(submission,
                                                      0,0,
                                                      cls.id)
    reply mappings
  end

  # Get mappings for an ontology
  get '/ontologies/:ontology/mappings' do
    ontology = ontology_from_acronym(@params[:ontology])
    if ontology.nil?
        error(404, "Ontology not found")
    end
    page, size = page_params
    submission = ontology.latest_submission
    if submission.nil?
        error(404, "Submission not found for ontology " + ontology.acronym)
    end
    mappings = LinkedData::Mappings.mappings_ontology(submission,
                                                      page,size,
                                                      nil)
    reply mappings
  end

  namespace "/mappings" do
    # Display all mappings
    get do
      ontologies = ontology_objects_from_params
      if ontologies.length != 2
        error(400, 
              "/mappings/ endpoint only supports filtering " +
              "on two ontologies using `?ontologies=ONT1,ONT2`")
      end

      page, size = page_params
      ont1 = ontologies.first
      ont2 = ontologies[1]
      sub1, sub2 = ont1.latest_submission, ont2.latest_submission
      if sub1.nil?
        error(404, "Submission not found for ontology " + ontologies[0].id.to_s)
      end
      if sub2.nil?
        error(404, "Submission not found for ontology " + ontologies[1].id.to_s)
      end
      mappings = LinkedData::Mappings.mappings_ontologies(sub1,sub2,
                                                          page,size)
      reply mappings
    end

    get "/recent" do
      size = params[:size] || 5
      if size > 50
        error 422, "Recent mappings only processes calls under 50"
      else
        mappings = LinkedData::Mappings.recent_rest_mappings(size + 15)
        reply mappings[0..size-1]
      end
    end

    # Display a single mapping - only rest
    get '/:mapping' do
      mapping_id = nil
      if params[:mapping] and params[:mapping].start_with?("http")
        mapping_id = params[:mapping]
        mapping_id = mapping_id.gsub("/mappings/","/rest_backup_mappings/")
        mapping_id = RDF::URI.new(params[:mapping])
      else
        mapping_id = 
          "http://data.bioontology.org/rest_backup_mappings/#{mapping_id}"
        mapping_id = RDF::URI.new(mapping_id)
      end
      mapping = LinkedData::Mappings.get_rest_mapping(mapping_id)
      if mapping
        reply mapping
      else
        error(404, "Mapping with id `#{mapping_id.to_s}` not found")
      end
    end

    # Create a new mapping
    post do
      error(400, "Input does not contain classes") if !params[:classes]
      if params[:classes].length > 2
        error(400, "Input does not contain at least 2 terms")
      end
      error(400, "Input does not contain mapping relation") if !params[:relation]
      error(400, "Input does not contain user creator ID") if !params[:creator]
      classes = []
      params[:classes].each do |class_id,ontology_id|
        o = ontology_id
        o =  o.start_with?("http://") ? ontology_id :
                                        ontology_uri_from_acronym(ontology_id)
        o = LinkedData::Models::Ontology.find(RDF::URI.new(o))
                                        .include(submissions: 
                                       [:submissionId, :submissionStatus]).first
        if o.nil?
          error(400, "Ontology with ID `#{ontology_id}` not found")
        end
        submission = o.latest_submission
        if submission.nil?
          error(400, 
     "Ontology with id #{ontology_id} does not have parsed valid submission")
        end
        submission.bring(ontology: [:acronym])
        c = LinkedData::Models::Class.find(RDF::URI.new(class_id))
                                    .in(submission)
                                    .first
        if c.nil?
          error(400, "Class ID `#{id}` not found in `#{submission.id.to_s}`")
        end
        classes << c
      end
      user_id = params[:creator].start_with?("http://") ? 
                    params[:creator].split("/")[-1] : params[:creator]
      user_creator = LinkedData::Models::User.find(user_id)
                          .include(:username).first
      if user_creator.nil?
        error(400, "User with id `#{params[:creator]}` not found")
      end
      process = LinkedData::Models::MappingProcess.new(
                    :creator => user_creator, :name => "REST Mapping")
      process.relation = RDF::URI.new(params[:relation])
      process.date = DateTime.now
      process_fields = [:source,:source_name, :comment]
      process_fields.each do |att|
        process.send("#{att}=",params[att]) if params[att]
      end
      process.save
      mapping = LinkedData::Mappings.create_rest_mapping(classes,process)
      reply(201, mapping)
    end

    # Delete a mapping
    delete '/:mapping' do
      mapping_id = RDF::URI.new(replace_url_prefix(params[:mapping]))
      mapping = LinkedData::Mappings.delete_rest_mapping(mapping_id)
      if mapping.nil?
        error(404, "Mapping with id `#{mapping_id.to_s}` not found")
      else
        halt 204
      end
    end
  end

  namespace "/mappings/statistics" do

    get '/ontologies' do
      expires 86400, :public
      persistent_counts = {}
      LinkedData::Models::MappingCount.where(pair_count: false)
      .include(:all)
      .all
      .each do |m|
        persistent_counts[m.ontologies.first] = m.count
      end
      reply persistent_counts
    end

    # Statistics for an ontology
    get '/ontologies/:ontology' do
      expires 86400, :public
      ontology = ontology_from_acronym(@params[:ontology])
      if ontology.nil?
        error(404, "Ontology #{@params[:ontology]} not found")
      end
      sub = ontology.latest_submission
      if sub.nil?
        error(404, "Ontology #{@params[:ontology]} does not have a submission")
      end
  
      persistent_counts = {}
      LinkedData::Models::MappingCount.where(pair_count: true)
                                      .and(ontologies: [ontology.acronym])
      .include(:all)
      .all
      .each do |m|
        other = m.ontologies.first
        if other == ontology.acronym
          other = m.ontologies[1]
        end
        persistent_counts[other] = m.count
      end
      reply persistent_counts
    end

  end

end
