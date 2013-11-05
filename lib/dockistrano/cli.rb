require 'thor'
require "dotenv"
Dotenv.load(".dockistrano")
ENV["DOCKISTRANO_ENVIRONMENT"] ||= "default"
ENV["DOCKER_HOST_IP"] ||= "127.0.0.1"
ENV["DOCKER_BINARY"] ||= "docker"

module Dockistrano

  class Cli < ::Thor

    desc "ps", "List all running containers in docker"
    def ps
      puts Docker.ps
    end

    desc "setup", "Sets up a host for starting the application"
    method_option "environment", aliases: "-e", default: ENV["DOCKISTRANO_ENVIRONMENT"], type: :string, desc: "Environment to start the container in"
    def setup
      say "Please execute the following command on the host to setup", :green
      say "\tmkdir -p #{current_service.directories_required_on_host.join(" ")}"
    end

    desc "status", "Status of the application"
    method_option "environment", aliases: "-e", default: ENV["DOCKISTRANO_ENVIRONMENT"], type: :string, desc: "Environment to start the container in"
    def status
      say "DOCKISTRANO_ENVIRONMENT: #{options["environment"]}", :green
      say "DOCKER_HOST_IP: #{ENV['DOCKER_HOST_IP']}", :green
      say "DOCKER_BINARY: #{ENV['DOCKER_BINARY']}", :green
      say ""
      say "Current application", :blue
      say "  registry: #{current_service.registry}"
      say "  image name: #{current_service.image_name}"
      say "  tag: #{current_service.tag}"
      say "  volumes:"
      current_service.volumes.each do |volume|
        say "    #{volume}"
      end
      say ""
      say "Dependencies", :blue
      current_service.backing_services.each do |name, service|
        say "  #{service.full_image_name}"
      end
      say ""
      say "Environment", :blue
      current_service.environment_variables.each do |key, value|
        say "  #{key}=#{value}"
      end
      say ""
      say "Hipache", :blue
      Hipache.new(ENV["DOCKER_HOST_IP"]).status.each do |host, ips|
        say "  #{host}: #{ips.join(", ")}"
      end
      say ""
    end

    desc "build", "Build and test a new application container"
    def build
      if current_service.build
        say_status "built", current_service.image_name
        if current_service.test
          say_status "tests passed", current_service.image_name
          current_service.push
          say_status "pushed", current_service.image_name
        else
          say_status "tests failed", current_service.image_name
          exit 1
        end
      else
        say_status "failed", current_service.image_name, :red
        exit 1
      end
    end

    desc "pull", "Pull new versions of dependencies"
    def pull
      current_service.backing_services(initialize: false).each do |name, service|
        if service.newer_version_available?
          service.pull
          say_status "Pulled", name
        else
          say_status "Uptodate", name, :white
        end
      end

      if current_service.newer_version_available?
        current_service.pull
        say_status "Pulled", current_service.image_name
      else
        say_status "Uptodate", current_service.image_name, :white
      end
    end

    desc "push", "Pushes a new version of this container"
    def push
      current_service.push
    end

    desc "start-services", "Starts the backing services"
    method_option "environment", aliases: "-e", default: ENV["DOCKISTRANO_ENVIRONMENT"], type: :string, desc: "Environment to start the container in"
    def start_services
      current_service.backing_services.each do |name, service|
        if service.running?
          say_status("Running", name, :white)
        else
          service.start
          say_status("Started", name)
        end
      end
    end

    desc "stop-all", "Stops the backing services"
    def stop_all
      current_service.stop
      say_status("Stopped", current_service.image_name)
      current_service.backing_services.each do |name, service|
        if service.running?
          service.stop
          say_status("Stopped", name)
        end
      end
    end

    desc "start", "Starts the application"
    method_option "environment", aliases: "-e", default: ENV["DOCKISTRANO_ENVIRONMENT"], type: :string, desc: "Environment to start the container in"
    def start
      if current_service.running?
        say_status("Running", current_service.image_name, :white)
      else
        current_service.start(options)
        say_status("Started", current_service.image_name)
      end
    rescue Dockistrano::Service::EnvironmentVariablesMissing => e
      say e.message, :red
    end

    desc "stop [ID]", "Stops the application or container with specified ID"
    def stop(id=nil)
      if id
        Docker.stop(id)
        Docker.remove_container(id)
        say_status("Stopped", id, :green)
      else
        current_service.stop
        say_status("Stopped", current_service.image_name, :green)
      end
    end

    desc "restart", "Restarts the application"
    method_option "environment", aliases: "-e", default: ENV["DOCKISTRANO_ENVIRONMENT"], type: :string, desc: "Environment to start the container in"
    def restart
      current_service.stop
      say_status("Stopped", current_service.image_name)
      current_service.start(options)
      say_status("Started", current_service.image_name)
    end

    desc "exec COMMAND", "Executes a command in the application and returns"
    method_option "environment", aliases: "-e", default: ENV["DOCKISTRANO_ENVIRONMENT"], type: :string, desc: "Environment to start the container in"
    def exec(*command)
      current_service.exec(command.join(" "), options)
    rescue Dockistrano::Service::EnvironmentVariablesMissing => e
      say e.message, :red
    end

    desc "console [COMMAND]", "Starts an interactive shell in the application"
    method_option "environment", aliases: "-e", default: ENV["DOCKISTRANO_ENVIRONMENT"], type: :string, desc: "Environment to start the container in"
    def console(*command)
      command = ["/bin/bash"] if command.empty?
      current_service.console(command.join(" "), options)
    rescue Dockistrano::Service::EnvironmentVariablesMissing => e
      say e.message, :red
    end

    desc "clean", "Cleans images and containers from docker"
    def clean
      Docker.clean
      Dockistrano::ServiceDependency.clear_cache
    end

    desc "logs [NAME]", "Prints the logs for the service"
    def logs(name=nil)
      if name and current_service.backing_services[name]
        service = current_service.backing_services[name]
        command_name = nil
      else
        service = current_service
        command_name = name
      end

      if service.running?
        say "Container #{service.image_name} running, attaching to output", :blue
        service.attach(command_name)
      else
        say "Container #{service.image_name} stopped, printing logs of last run", :blue
        service.logs(command_name)
      end
    end

    desc "version", "Prints version information"
    def version
      say "Dockistrano version: #{Dockistrano::VERSION}"
    end

    def method_missing(*args)
      command = args[0]
      if command and current_service.config["aliases"] and current_service.config["aliases"][command.to_s]
        args.shift
        Kernel.exec("doc #{current_service.config["aliases"][command.to_s]} #{args.join(" ")}")
      else
        super
      end
    end

    private

    # Returns the current service
    def current_service
      @service ||= Service.factory(Dir.pwd, options["environment"])
    rescue Dockistrano::Service::ConfigurationFileMissing
      say "No configuration file found in current directory. config/dockistrano.yml missing", :red
      exit 1
    end

  end
end
