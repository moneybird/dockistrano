module Dockistrano

  class Registry

    attr_reader :name

    def initialize(name)
      @name = name
    end

    class RepositoryNotFoundInRegistry < StandardError
    end

    def tags_for_image(image_name)
      result = MultiJson.load(get("repositories", image_name, "tags").body)
      if result["error"]
        if result["error"] == "Repository not found"
          raise RepositoryNotFoundInRegistry.new("Could not find repository #{image_name} in registry #{name}")
        else
          raise result["error"]
        end
      else
        result
      end
    end

    def latest_id_for_image(image_name, tag)
      response = get("repositories", image_name, "tags", tag)
      if response.kind_of?(Net::HTTPNotFound)
        nil
      else
        MultiJson.load(response.body)
      end
    end

    def to_s
      name
    end

    private

    def get(*url)
      uri = URI.parse("http://#{name}/v1/#{url.join("/")}")
      Net::HTTP.get_response(uri)
    end

  end
end
