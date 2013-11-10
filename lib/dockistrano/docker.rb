require 'cocaine'
require 'multi_json'

module Dockistrano

  # Class for communication with Docker. Uses two means of communication:
  #
  # - Actions on containers are executed by calling the docker binary with an
  #   ip address of the Docker location. The docker command line client is best
  #   capable of executing the actions for building images, running containers and
  #   managing containers.
  # - Queries are executed using the HTTP API of docker. This API is exposed via HTTP
  #   and returns JSON. This allows us to easily parse and return the information.
  #
  # This class uses two environment variables:
  #
  #   DOCKER_BINARY  - Location of the docker binary on your system
  #   DOCKER_HOST_IP - IP address or host of the docker server
  #
  class Docker

    class EnvironmentVariableMissing < StandardError
    end

    # Returns the docker command as a string: 'docker -H 127.0.0.1'
    def self.docker_command
      raise EnvironmentVariableMissing.new("Missing DOCKER_BINARY in environment, please provide the location of the docker binary") unless ENV["DOCKER_BINARY"]
      raise EnvironmentVariableMissing.new("Missing DOCKER_HOST_IP in environment, please provide the host or ip address of the docker server") unless ENV["DOCKER_HOST_IP"]
      "#{ENV['DOCKER_BINARY']} -H #{ENV['DOCKER_HOST_IP']}"
    end

    # Executes the given command on the command line
    def self.execute(command, mode=:string_result)
      case mode
      when :string_result
        Dockistrano::CommandLine.command_with_result("#{docker_command} #{command.collect { |c| c.kind_of?(String) ? c : arguments(c) }.join(" ")}".strip)
      when :stream
        Dockistrano::CommandLine.command_with_stream("#{docker_command} #{command.collect { |c| c.kind_of?(String) ? c : arguments(c) }.join(" ")}".strip)
      else
        Dockistrano::CommandLine.command_with_interaction("#{docker_command} #{command.collect { |c| c.kind_of?(String) ? c : arguments(c) }.join(" ")}".strip)
      end
    end

    def self.ps(options={})
      execute(["ps", options])
    end

    def self.stop(id)
      execute(["stop", id])
    end

    def self.run(full_image_name, options={})
      if (command = options.delete(:command))
        execute(["run", options, full_image_name, command])
      else
        execute(["run", options, full_image_name])
      end
    end

    def self.exec(full_image_name, options={})
      if (command = options.delete(:command))
        execute(["run", options, full_image_name, command], :stream)
      else
        execute(["run", options, full_image_name], :stream)
      end
    end

    def self.console(full_image_name, options={})
      options["t"] = true
      options["i"] = true
      if (command = options.delete(:command))
        execute(["run", options, full_image_name, command], :interaction)
      else
        execute(["run", options, full_image_name], :interaction)
      end
    end

    def self.build(full_image_name)
      execute(["build", { t: full_image_name }, "."], :stream)
    end

    def self.pull(full_image_name, tag)
      execute(["pull", { t: tag }, full_image_name])
    end

    def self.push(image_name, tag)
      execute(["push", image_name, tag], :stream)
    end

    def self.logs(id)
      execute(["logs", id], :stream)
    end

    def self.attach(id)
      execute(["attach", id], :stream)
    end

    def self.remove_container(name)
      execute(["rm", name])
    end

    def self.clean
      Dockistrano::CommandLine.command_with_stream("#{docker_command} rmi $(#{docker_command} images -a | grep \"^<none>\" | awk '{print $3}')")
      Dockistrano::CommandLine.command_with_stream("#{docker_command} rm $(#{docker_command} ps -a -q)")
    end

    def self.running?(image_name)
      request(["containers", image_name, "json"])["State"]["Running"]
    rescue ResourceNotFound
      false
    end

    # Returns the id of the last container with an error
    def self.last_run_container_id(full_image_name)
      request(["containers", "json?all=1"]).each do |container|
        return container["Id"] if container["Image"] == full_image_name and container["Command"] != "cat /dockistrano.yml"
      end
      nil
    end

    def self.image_id(full_image_name)
      inspect_image(full_image_name)["id"]
    end

    class ImageNotFound < StandardError
    end

    def self.inspect_image(full_image_name)
      response = request(["images", full_image_name, "json"])
    rescue ResourceNotFound => e
      raise ImageNotFound.new(e.message)
    end

    def self.inspect_container(name)
      request(["containers", name, "json"])
    end

    def self.stop_all_containers_from_image(full_image_name)
      containers = request(["containers", "json"])
      containers.each do |container|
        execute(["stop", container["Id"]]) if container["Image"] == full_image_name
      end
    end

    def self.tags_for_image(image_name)
      images = request(["images", "json"])
      [].tap do |tags|
        images.each do |image|
          tags << image["Tag"] if image["Repository"] == image_name
        end
      end
    end

    private

    def self.request(path)
      uri = URI.parse("http://#{ENV['DOCKER_HOST_IP']}:4243/#{path.join("/")}")
      response = Net::HTTP.get_response(uri)
      if response.kind_of?(Net::HTTPNotFound)
        raise ResourceNotFound.new("Could not find #{path.join("/")}: #{response.body}")
      end

      MultiJson.load(response.body)
    end

    class ResourceNotFound < StandardError
    end

    def self.arguments(options)
      options.collect do |k,v|
        case v
        when TrueClass
          "-#{k}"
        when Array
          v.collect { |av| "-#{k} #{av}" }.join(" ").strip
        when Hash
          v.collect { |ak, av|
            if av
              "-#{k} #{ak}='#{av}'"
            else
              ""
            end
          }.join(" ").strip
        else
          "-#{k} #{v}"
        end
      end.join(" ").strip
    end

  end
end
