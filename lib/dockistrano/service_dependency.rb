module Dockistrano

  class ServiceDependency

    # Creates a new service instance based on the name and configuration. When
    # configuration is not local, the configuration is fetched from Github and
    # processed.
    def self.factory(service, name, config)
      ServiceDependency.new(service, name, config).backing_service
    end

    class DefaultEnvironmentMissingInConfiguration < StandardError
    end

    attr_reader :service, :name, :config

    def initialize(service, name, config)
      @service = service
      @name = name
      @config = config
    end

    def backing_service
      @backing_service ||= begin
        backing_service = Service.new("default" => {
          "registry"    => service.registry,
          "image_name"  => name,
          "tag"         => service.tag,
          "backing_service_env" =>  config
        })

        backing_service.tag = tag_with_fallback(service.registry, name, service.tag)

        begin
          loaded_config = load_config
          if loaded_config and loaded_config["default"]
            backing_service.config = loaded_config["default"]
          else
            raise DefaultEnvironmentMissingInConfiguration.new("No 'default' configuration found in /dockistrano.yml file in #{name} container.")
          end
        rescue ContainerConfigurationMissing
          puts "Warning: no configuration file found for service #{name}."
        rescue HostDirectoriesMissing
          puts "Error: missing host directory configuration for #{name}. Please execute `doc setup`"
          exit 1
        end

        backing_service
      end
    end

    def load_config
      load_from_cache || load_from_image
    end

    def load_from_cache
      image_id = backing_service.image_id
      if image_id and File.exists?("tmp/configuration_cache/#{image_id}")
        YAML.load_file("tmp/configuration_cache/#{image_id}")
      else
        nil
      end
    end

    class ContainerConfigurationMissing < StandardError
    end

    class HostDirectoriesMissing < StandardError
    end

    def load_from_image
      raw_config = Docker.run(backing_service.full_image_name, command: "cat /dockistrano.yml")
      if raw_config.empty? or raw_config.include?("No such file or directory")
        if raw_config.include?("failed to mount")
          raise HostDirectoriesMissing
        else
          raise ContainerConfigurationMissing
        end
      else
        FileUtils.mkdir_p("tmp/configuration_cache")
        file = File.open("tmp/configuration_cache/#{backing_service.image_id}", "w+")
        file.write(raw_config)
        file.close

        config = YAML.load(raw_config)
      end
    end

    class NoTagFoundForImage < StandardError
    end

    def tag_with_fallback(registry, image_name, tag)
      fallback_tags = [tag, "develop", "master", "latest"]

      available_tags = Docker.tags_for_image("#{registry}/#{image_name}")

      begin
        tag_suggestion = fallback_tags.shift
        final_tag = tag_suggestion if available_tags.include?(tag_suggestion)
      end while !final_tag and fallback_tags.any?

      if final_tag
        final_tag
      else
        raise NoTagFoundForImage.new("No tag found for image #{image_name}, locally available tags: #{available_tags} `doc pull` for more tags from repository.")
      end
    end

    def self.clear_cache
      `rm -rf tmp/configuration_cache/`
    end

  end
end
