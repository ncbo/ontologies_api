class RepliesController < ApplicationController

  # Display all replies for a note
  get "/notes/:noteid/replies" do
    check_last_modified_collection(LinkedData::Models::Notes::Reply)
    noteid = LinkedData::Models::Note.id_prefix + params["noteid"]
    note = LinkedData::Models::Note.find(RDF::IRI.new(noteid)).include(:reply).first
    error 404, "Note `#{noteid}` not found" if note.nil?
    reply note.reply
  end

  namespace "/replies" do

    # Display all replies
    get '' do
      check_last_modified_collection(LinkedData::Models::Notes::Reply)
      replies = LinkedData::Models::Notes::Reply.where.include(LinkedData::Models::Notes::Reply.goo_attrs_to_load(includes_param)).to_a
      reply replies
    end


    # Display a single reply
    get "/:replyid" do
      _reply = LinkedData::Models::Notes::Reply.find(params["replyid"]).first
      error 404, "Reply #{params["replyid"]} not found" if _reply.nil?
      check_last_modified(_reply)
      _reply.bring(*LinkedData::Models::Notes::Reply.goo_attrs_to_load(includes_param))
      reply 200, _reply
    end

    # Create a reply with the given noteid
    post do
      noteid = params["parent"]
      note = LinkedData::Models::Note.find(uri_as_needed(noteid)).include(LinkedData::Models::Note.attributes).first

      _reply = instance_from_params(LinkedData::Models::Notes::Reply, params)

      unless note || _reply.parent
        error 422, "You must provide either a `note` or a `parent` to associate the reply with"
      end

      if _reply.valid?
        _reply.save
        if note
          begin
            note.reply = note.reply.dup.push(_reply)
            note.save
          rescue
            _reply.delete
            error 400, note.errors
          end
        end
      else
        error 400, _reply.errors
      end
      reply 201, _reply
    end

    # Update an existing submission of an reply
    patch '/:replyid' do
      replyid = params["replyid"]
      _reply = LinkedData::Models::Notes::Reply.find(replyid).include(LinkedData::Models::Notes::Reply.attributes).first

      if _reply.nil?
        error 400, "Reply does not exist, please create using HTTP POST before modifying"
      else
        populate_from_params(_reply, params)

        if _reply.valid?
          _reply.save
        else
          error 400, _reply.errors
        end
      end
      halt 204
    end

    # Delete a reply
    delete '/:replyid' do
      _reply = LinkedData::Models::Notes::Reply.find(params["replyid"]).first
      _reply.delete
      halt 204
    end
  end
end
