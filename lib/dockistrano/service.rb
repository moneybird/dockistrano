require 'yaml'
require 'net/http'

module Dockistrano

  class Service

    attr_reader :dependencies, :config, :image_name, :registry,
      :tag, :test_command, :provides_env, :backing_service_env,
      :data_directories, :environment, :host, :additional_commands,
      :mount_src

    attr_writer :tag

    class ConfigurationFileMissing < StandardError
    end

    def self.factory(path, environment="default")
      config = if File.exists?(File.join(path, "config", "dockistrano.yml"))
        YAML.load_file(File.join(path, "config", "dockistrano.yml"))
      elsif File.exists?(File.join(path, "dockistrano.yml"))
        YAML.load_file(File.join(path, "dockistrano.yml"))
      else
        raise ConfigurationFileMissing
      end

      environment ||= "default"

      Service.new(config, environment)
    end

    def initialize(config, environment="default")
      @full_config = config
      self.environment = environment
    end

    def config=(config)
      @config = config
      @dependencies = config["dependencies"] || {}
      @image_name ||= config["image_name"] || Git.repository_name
      @tag ||= config["tag"] || Git.branch
      @registry ||= config["registry"]
      @host ||= config["host"]
      @test_command = config["test_command"]
      @mount_src = config["mount_src"]
      @provides_env = config["provides_env"] || {}
      @additional_commands = config["additional_commands"] || {}
      @data_directories = config["data_directories"] || []
      @backing_service_env ||= {}
      @backing_service_env.merge!(config["backing_service_env"] || {})

      config["environment"] ||= {}
    end

    class EnvironmentNotFoundInConfiguration < StandardError
    end

    def environment=(environment)
      if @full_config[environment]
        self.config = @full_config[environment]
      else
        raise EnvironmentNotFoundInConfiguration.new("Environment '#{environment}' not found in configuration (image: #{@full_config["image_name"]}), available: #{@full_config.keys.join(", ")}")
      end
    end

    def registry_instance
      @registry_instance ||= Registry.new(registry)
    end

    def image_id
      Docker.image_id(full_image_name)
    rescue Dockistrano::Docker::ImageNotFound
      nil
    end

    def full_image_name
      "#{registry}/#{image_name}:#{tag}"
    end

    def full_image_name_with_fallback
      "#{registry}/#{image_name}:#{tag_with_fallback}"
    end

    # Builds a new image for this service
    def build
      previous_image_id = image_id
      Docker.build(full_image_name)
      if previous_image_id == image_id
        # If the image id hasn't changed the build was not successfull
        false
      else
        true
      end
    end

    # Tests the image of this services by running a test command
    def test
      environment = "test"
      unless test_command.nil? or test_command.empty?
        ensure_backing_services
        create_data_directories
        Docker.exec(full_image_name, command: test_command, e: checked_environment_variables, v: volumes)
      else
        true
      end
    end

    # Ensures that the right backing services are running to execute this services
    # When a backing services is not running it is started
    def ensure_backing_services
      backing_services.each do |name, service|
        service.start unless service.running?
      end
    end

    # Stops the container of the current service
    def stop
      if !host.nil?
        hipache = Hipache.new(ENV['DOCKER_HOST_IP'])
        if host.kind_of?(String)
          hipache.unregister(image_name, host, ip_address, port)
        else
          host.each do |hostname, port|
            hipache.unregister(image_name, hostname, ip_address, port)
          end
        end
      end

      Docker.stop_all_containers_from_image(full_image_name)
    end

    # Returns if this service is running
    def running?
      Docker.running_container_id(full_image_name)
    end

    # Pulls backing services for this service
    def pull_backing_services
      backing_services.each do |name, service|
        service.pull
      end
    end

    # Pulls the service's container
    def pull
      Dockistrano::Docker.pull("#{registry}/#{image_name}", tag_with_fallback)
    end

    # Pushes the local image for this service to the registry
    def push
      Dockistrano::Docker.push("#{registry}/#{image_name}", tag)
    end

    # Starts this service
    def start(options={})
      ensure_backing_services
      create_data_directories
      environment = checked_environment_variables

      if additional_commands.any?
        additional_commands.each do |name, command|
          Docker.run(full_image_name, e: environment, v: volumes, p: ports, d: true, command: command)
        end
      end

      Docker.run(full_image_name, e: environment, v: volumes, p: ports, d: true)

      if !host.nil?
        hipache = Hipache.new(ENV['DOCKER_HOST_IP'])
        if host.kind_of?(String)
          hipache.register(image_name, host, ip_address, port)
        else
          host.each do |hostname, port|
            hipache.register(image_name, hostname, ip_address, port)
          end
        end
      end
    end

    # Runs a command in this container
    def run(command, options={})
      Docker.run(full_image_name_with_fallback, command: command, e: environment_variables, v: volumes, p: ports)
    end

    # Executes a command in this container
    def exec(command, options={})
      create_data_directories
      Docker.exec(full_image_name_with_fallback, command: command, e: environment_variables, v: volumes, p: ports)
    end

    # Starts a console in the docker container
    def console(command, options={})
      create_data_directories
      Docker.console(full_image_name_with_fallback, command: command, e: environment_variables, v: volumes, p: ports)
    end

    # Lists all backing services for this service
    def backing_services(options={})
      initialize = options.delete(:initialize)
      initialize = true if initialize.nil?
      @backing_services ||= {}.tap do |hash|
        dependencies.collect do |name, config|
          hash[name] = ServiceDependency.factory(self, name, config, initialize)
        end
      end
    end

    # Returns an array of environment variables
    def environment_variables
      vars = {}

      config["environment"].each do |name, value|
        vars[name.upcase] = value
      end

      backing_services.each do |name, backing_service|
        vars["#{name.upcase}_IP"] = backing_service.ip_address
        vars["#{name.upcase}_PORT"] = backing_service.port

        backing_service.backing_service_env.each do |k,v|
          vars["#{name.upcase}_#{k.upcase}"] = v
        end

        vars.merge!(backing_service.provided_environment_variables)
      end

      vars.each do |key, value|
        vars.each do |replacement_key, replacement_value|
          unless vars[key].nil? or replacement_value.nil?
            vars[key] = vars[key].gsub('$'+replacement_key, replacement_value)
          end
        end
      end

      vars
    end

    def provided_environment_variables
      provides_env
    end

    # Returns the mounted volumes for this service
    def volumes
      [].tap do |volumes|
        volumes << "/dockistrano/#{image_name.gsub("-", "_")}/data:/dockistrano/data"
        if mount_src and !mount_src.empty?
          volumes << "/dockistrano/#{image_name.gsub("-", "_")}/src:#{mount_src}"
        end
      end
    end

    def directories_required_on_host
      (volumes.collect { |v| v.split(":").first } + backing_services.values.map(&:directories_required_on_host)).flatten
    end

    # Returns a list of available tags in the registry for the image
    def available_tags
      @available_tags ||= begin
        registry_instance.tags_for_image(image_name)
      rescue Dockistrano::Registry::RepositoryNotFoundInRegistry
        []
      end
    end

    class NoTagFoundForImage < StandardError
    end

    # Returns the tag that is available with fallback.
    def tag_with_fallback
      fallback_tags = [tag, "develop", "master", "latest"]

      begin
        tag_suggestion = fallback_tags.shift
        final_tag = tag_suggestion if available_tags.include?(tag_suggestion)
      end while !final_tag and fallback_tags.any?

      if final_tag
        final_tag
      else
        raise NoTagFoundForImage.new("No tag found for image #{image_name}, wanted tag #{tag}, available tags: #{available_tags}")
      end
    end

    def ip_address
      container_settings["NetworkSettings"]["IPAddress"] if running?
    end

    def port
      container_settings["NetworkSettings"]["PortMapping"]["Tcp"].keys.first if running?
    end

    def ports
      (config["ports"] || {}).collect { |k,v| "#{k}:#{v}" }
    end

    def attach
      Docker.attach(Docker.running_container_id(full_image_name))
    end

    def logs
      Docker.logs(Docker.last_run_container_id(full_image_name))
    end

    def create_data_directories
      if data_directories.any?
        image_config = Docker.inspect_image(full_image_name_with_fallback)
        image_user = image_config["container_config"]["User"]

        command = "mkdir -p #{data_directories.collect { |dir| "/dockistrano/data/#{dir}"}.join(" ") }; "
        command += "chown #{image_user}:#{image_user} #{data_directories.collect { |dir| "/dockistrano/data/#{dir}"}.join(" ") }"
        bash_command = "/bin/bash -c '#{command}'"
        Docker.run(full_image_name_with_fallback, command: bash_command, v: volumes, e: environment_variables, u: "root")
      end
    end

    def newer_version_available?
      registry_image_id = registry_instance.latest_id_for_image(image_name, tag_with_fallback)
      registry_image_id and image_id != registry_image_id
    end

    private

    def container_settings
      @container_settings ||= Docker.inspect_container(Docker.running_container_id(full_image_name))
    end

    class EnvironmentVariablesMissing < StandardError
    end

    def checked_environment_variables
      vars = environment_variables
      if (empty_vars = vars.select { |k,v| v.nil? }).any?
        raise EnvironmentVariablesMissing.new("Unable to execute container because of missing environment variables: #{empty_vars.keys.join(", ")}")
      else
        vars
      end
    end

  end
end
