# Process-level TTL cache of the full ontology list (issue #244).
#
# Loading all ~1,200 ontologies from the backend accounted for ~97% of
# /search response time because both branches of restricted_ontologies
# reloaded the list on every request. The list changes on the scale of
# days, so it is loaded once per TTL window per worker instead.
#
# Staleness contract: ontology additions/removals and ACL or
# viewingRestriction changes take up to the TTL to propagate (per
# worker). Per-user visibility filtering (slice/ACL) remains per-request
# in the callers; only the raw list is cached.
#
# TTL comes from LinkedData::OntologiesAPI.settings.ontology_list_cache_ttl
# (seconds, default 300). A value of 0 disables caching entirely.
#
# NOTE: the returned array is a defensive copy, but the Ontology objects
# in it are shared across requests within a worker. Loading further
# attributes on them (bring) is safe; assigning attributes is not.
class OntologyListCache
  @lock = Mutex.new
  @cached = nil

  class << self
    def all
      ttl = ttl_seconds
      return load_ontologies if ttl <= 0

      @lock.synchronize do
        if @cached.nil? || clock_now >= @cached[:expires_at]
          objects = load_ontologies
          @cached = { objects: objects, expires_at: clock_now + ttl }
        end
        @cached[:objects].dup
      end
    end

    def invalidate!
      @lock.synchronize { @cached = nil }
    end

    private

    def ttl_seconds
      LinkedData::OntologiesAPI.settings.ontology_list_cache_ttl.to_i
    end

    def load_ontologies
      LinkedData::Models::Ontology.where.include(*load_attributes).to_a
    end

    # Union of the attributes every caller of the cached list needs:
    # serialization defaults (previous behavior of the load-all sites),
    # access-control attrs (so restricted_ontologies needs no second
    # query), and viewOf (site-wide view filtering moved into Ruby).
    def load_attributes
      attrs = LinkedData::Models::Ontology.goo_attrs_to_load
      attrs += LinkedData::Models::Ontology.access_control_load_attrs.to_a
      attrs << :viewOf
      attrs.uniq
    end

    def clock_now
      Time.now
    end
  end
end
