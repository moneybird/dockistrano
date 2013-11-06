require 'spec_helper'

describe Dockistrano::Service do

  subject { described_class.new(config, "default") }
  let(:config) {{
    "default" => {
      "image_name" => "image",
      "tag"        => "tag",
      "registry"   => "index.provide.dev:5000"
    }
  }}

  context ".factory" do
    it "initializes a service for the current directory" do
      service = described_class.factory("spec/fixtures/project_1")
      expect(service.config).to eq({
        "registry" => "my.registry.com:5000",
        "image_name" => "project_1",
        "dependencies" => {
          "redis" => "git@github.com:username/redis.git",
          "memcached" => "git@github.com:username/memcached.git"
        },
        "environment" => {}
      })
    end
  end

  context "#config=" do
    subject { described_class.new({ "default" => {} }, "default") }

    it "uses the name of the git repository as the name of the image" do
      expect(Dockistrano::Git).to receive(:repository_name).and_return("repo_name")
      subject.config = {}
      expect(subject.image_name).to eq("repo_name")
    end

    it "uses the git branch as the tag" do
      expect(Dockistrano::Git).to receive(:branch).and_return("develop")
      subject.config = {}
      expect(subject.tag).to eq("develop")
    end
  end

  context "#environment=" do
    let(:config) {{
      "default" => { "test_command" => "default" },
      "test" => { "test_command" => "test" }
    }}

    it "sets the config to the new environment" do
      subject.environment = "test"
      expect(subject.config).to eq({ "test_command" => "test", "environment" => {} })
    end

    it "raises an error when the environment is not found" do
      expect {
        subject.environment = "foobar"
      }.to raise_error(Dockistrano::Service::EnvironmentNotFoundInConfiguration)
    end
  end

  context "#registry_instance" do
    it "returns an instance of the registry" do
      expect(Dockistrano::Registry).to receive(:new).and_return(instance = double)
      expect(subject.registry_instance).to eq(instance)
    end
  end

  context "#image_id" do
    it "returns the image id of the current container" do
      expect(Dockistrano::Docker).to receive(:image_id).with(subject.full_image_name).and_return(123456789)
      expect(subject.image_id).to eq(123456789)
    end

    it "returns nil when the image is not found" do
      expect(Dockistrano::Docker).to receive(:image_id).with(subject.full_image_name).and_raise(Dockistrano::Docker::ImageNotFound)
      expect(subject.image_id).to be_nil
    end
  end

  context "#full_image_name" do
    let(:config) {{
      "default" => {
        "image_name" => "image",
        "tag"        => "tag",
        "registry"   => "index.provider.dev:5000"
      }
    }}

    it "returns the name with registry and tag" do
      expect(subject.full_image_name).to eq("index.provider.dev:5000/image:tag")
    end
  end

  context "#build" do
    it "builds the container" do
      allow(subject).to receive(:image_id).and_return(123, 456)
      allow(subject).to receive(:full_image_name).and_return("full_image_name")
      expect(Dockistrano::Docker).to receive(:build).with("full_image_name")
      expect(subject.build).to be_true
    end

    it "returns false when the build didn't change the image id" do
      allow(subject).to receive(:image_id).and_return(123, 123)
      allow(subject).to receive(:full_image_name).and_return("full_image_name")
      expect(Dockistrano::Docker).to receive(:build).with("full_image_name")
      expect(subject.build).to be_false
    end
  end

  context "#test" do
    before do
      allow(subject).to receive(:full_image_name).and_return("full_image_name")
      allow(subject).to receive(:test_command).and_return("rake test")
      allow(subject).to receive(:checked_environment_variables).and_return(environment_variables)
      allow(subject).to receive(:volumes).and_return(volumes)
    end

    let(:environment_variables) { double }
    let(:volumes) { double }

    it "tests the container" do
      expect(subject).to receive(:ensure_backing_services)
      expect(Dockistrano::Docker).to receive(:exec).with("full_image_name", command: "rake test", e: environment_variables, v: volumes).and_return(true)
      expect(subject.test).to be_true
    end

    it "returns true when no test command is provided" do
      allow(subject).to receive(:test_command).and_return("")
      expect(subject.test).to be_true
    end
  end

  context "#ensure_backing_services" do
    before do
      allow(subject).to receive(:backing_services).and_return({ "service_1" => service_1, "service_2" => service_2 })
    end
    let(:service_1) { double }
    let(:service_2) { double }

    it "starts services that are not running" do
      expect(service_1).to receive(:running?).and_return(true)
      expect(service_2).to receive(:running?).and_return(false)

      expect(service_2).to receive(:start)
      subject.ensure_backing_services
    end

    it "doesn't start services that are already running" do
      expect(service_1).to receive(:running?).and_return(true)
      expect(service_2).to receive(:running?).and_return(true)

      expect(service_1).to_not receive(:start)
      expect(service_2).to_not receive(:start)
      subject.ensure_backing_services
    end
  end

  context "#stop" do
    before do
      allow(Dockistrano::Docker).to receive(:stop)
      allow(Dockistrano::Docker).to receive(:remove_container)
      allow(subject).to receive(:additional_commands).and_return({ "worker" => "sidekiq" })
      allow(subject).to receive(:update_hipache)
    end

    it "stops the container" do
      expect(Dockistrano::Docker).to receive(:stop).with(subject.image_name)
      subject.stop
    end

    it "removes the container from Docker" do
      expect(Dockistrano::Docker).to receive(:remove_container).with(subject.image_name)
      subject.stop
    end

    it "stops containers running additional commands" do
      expect(Dockistrano::Docker).to receive(:stop).with("#{subject.image_name}_worker")
      expect(Dockistrano::Docker).to receive(:remove_container).with("#{subject.image_name}_worker")
      subject.stop
    end

    it "updates Hipache" do
      expect(subject).to receive(:update_hipache).with(false)
      subject.stop
    end
  end

  context "#running?" do
    before do
      allow(subject).to receive(:full_image_name).and_return("image_name:tag")
    end

    it "returns true when the service is running" do
      expect(Dockistrano::Docker).to receive(:running_container_id).with("image_name:tag").and_return("423c138040f1")
      expect(subject.running?).to eq("423c138040f1")
    end

    it "returns false when the service is not running" do
      expect(Dockistrano::Docker).to receive(:running_container_id).with("image_name:tag").and_return(nil)
      expect(subject.running?).to eq(nil)
    end
  end

  context "#pull_backing_services" do
    before do
      allow(subject).to receive(:backing_services).and_return({ "service_1" => service_1, "service_2" => service_2 })
    end
    let(:service_1) { double }
    let(:service_2) { double }

    it "pulls each backing service" do
      expect(service_1).to receive(:pull)
      expect(service_2).to receive(:pull)
      subject.pull_backing_services
    end
  end

  context "#pull" do
    before do
      allow(subject).to receive(:registry).and_return("registry.net:5000")
      allow(subject).to receive(:image_name).and_return("image_name")
      allow(subject).to receive(:tag_with_fallback).and_return("latest")
    end

    it "pulls the service's container" do
      expect(Dockistrano::Docker).to receive(:pull).with("registry.net:5000/image_name", "latest")
      subject.pull
    end
  end

  context "#push" do
    it "pushes the current container to the registry" do
      allow(subject).to receive(:registry).and_return("registry.net:5000")
      allow(subject).to receive(:image_name).and_return("image_name")
      allow(subject).to receive(:tag).and_return("tag")
      expect(Dockistrano::Docker).to receive(:push).with("registry.net:5000/image_name", "tag")
      subject.push
    end
  end

  context "#update_hipache" do
    let(:hipache) { double }
    let(:hipache_service) { double }

    before do
      allow(Dockistrano::Hipache).to receive(:new).and_return(hipache)
      allow(subject).to receive(:backing_services).and_return({ "hipache" => hipache_service })
      allow(hipache_service).to receive(:ip_address).and_return("172.168.1.1")
    end

    it "registers the host in Hipache when the server is up" do
      allow(subject).to receive(:host).and_return({ "hostname.dev" => "8000" })
      expect(subject).to receive(:ip_address).and_return("33.33.33.33")
      expect(hipache).to receive(:register).with(subject.image_name, "hostname.dev", "33.33.33.33", "8000")
      subject.update_hipache(true)
    end

    it "unregisters the host in Hipache when the server is down" do
      allow(subject).to receive(:host).and_return({ "hostname.dev" => "8000" })
      expect(subject).to receive(:ip_address).and_return("33.33.33.33")
      expect(hipache).to receive(:unregister).with(subject.image_name, "hostname.dev", "33.33.33.33", "8000")
      subject.update_hipache(false)
    end
  end

  context "#start" do
    let(:environment) { double }
    let(:volumes) { double }
    let(:ports) { double }
    let(:links) { double }

    before do
      allow(subject).to receive(:update_hipache)
      allow(subject).to receive(:ensure_backing_services)
      allow(subject).to receive(:create_data_directories)
      allow(subject).to receive(:checked_environment_variables).and_return(environment)
      allow(subject).to receive(:volumes).and_return(volumes)
      allow(subject).to receive(:ports).and_return(ports)
      allow(subject).to receive(:link_backing_services).and_return(links)
      allow(Dockistrano::Docker).to receive(:run)
    end

    it "ensures backing services are running" do
      expect(subject).to receive(:ensure_backing_services)
      subject.start
    end

    it "creates data directories" do
      expect(subject).to receive(:create_data_directories)
      subject.start
    end

    it "starts additional container when additional commands are configured" do
      allow(subject).to receive(:additional_commands).and_return({ "worker" => "sidekiq start" })
      expect(Dockistrano::Docker).to receive(:run).with(subject.full_image_name, name: "#{subject.image_name}_worker", link: links, e: environment, v: volumes, d: true, command: "sidekiq start")
      subject.start
    end

    it "starts the container with the default command, providing env variables and volumes" do
      expect(Dockistrano::Docker).to receive(:run).with(subject.full_image_name, name: subject.image_name, link: links, e: environment, v: volumes, p: ports, d: true)
      subject.start
    end

    it "updates Hipache" do
      expect(subject).to receive(:update_hipache)
      subject.start
    end
  end

  context "#run" do
    it "runs the command inside the container" do
      allow(subject).to receive(:full_image_name_with_fallback).and_return("image:develop")
      allow(subject).to receive(:environment_variables).and_return(environment = double)
      allow(subject).to receive(:volumes).and_return(volumes = double)
      allow(subject).to receive(:link_backing_services).and_return(link = double)
      expect(Dockistrano::Docker).to receive(:run).with(subject.full_image_name_with_fallback, link: link, e: environment, v: volumes, command: "foobar")
      subject.run("foobar")
    end
  end

  context "#exec" do
    it "executes the command inside the container" do
      allow(subject).to receive(:full_image_name_with_fallback).and_return("image:develop")
      allow(subject).to receive(:environment_variables).and_return(environment = double)
      allow(subject).to receive(:volumes).and_return(volumes = double)
      allow(subject).to receive(:link_backing_services).and_return(link = double)
      expect(subject).to receive(:create_data_directories)
      expect(Dockistrano::Docker).to receive(:exec).with(subject.full_image_name_with_fallback, link: link, e: environment, v: volumes, command: "foobar")
      subject.exec("foobar")
    end
  end

  context "#console" do
    it "runs the command inside the container" do
      allow(subject).to receive(:full_image_name_with_fallback).and_return("image:develop")
      allow(subject).to receive(:environment_variables).and_return(environment = double)
      allow(subject).to receive(:volumes).and_return(volumes = double)
      allow(subject).to receive(:link_backing_services).and_return(link = double)
      expect(subject).to receive(:create_data_directories)
      expect(Dockistrano::Docker).to receive(:console).with(subject.full_image_name_with_fallback, link: link, e: environment, v: volumes, command: "foobar")
      subject.console("foobar")
    end
  end

  context "#backing_services" do
    let(:service) { double }

    before do
      allow(subject).to receive(:dependencies).and_return({"postgresql" => {}})
    end

    it "returns a hash with backing services" do
      expect(Dockistrano::ServiceDependency).to receive(:factory).with(subject, "postgresql", {}, true).and_return(service)
      expect(subject.backing_services).to eq({ "postgresql" => service })
    end

    it "returns a hash with uninitialized backing services" do
      expect(Dockistrano::ServiceDependency).to receive(:factory).with(subject, "postgresql", {}, false).and_return(service)
      expect(subject.backing_services(initialize: false)).to eq({ "postgresql" => service })
    end
  end

  context "#link_backing_services" do
    it "returns an array with image names of backing services" do
      allow(subject).to receive(:backing_services).and_return({
        "postgresql" => double(image_name: "postgresql"),
        "redis" => double(image_name: "redis")
      })
      expect(subject.link_backing_services).to eq(["postgresql:postgresql", "redis:redis"])
    end
  end

  context "#environment_variables" do
    let(:backing_service){
      double(
        ip_address: "172.0.0.1",
        port: "1245",
        backing_service_env: { database: "dockistrano_development" },
        provided_environment_variables: { "DATABASE_URL" => "postgres://postgres@172.0.0.1/$POSTGRESQL_DATABASE"}
      )
    }

    before do
      allow(subject).to receive(:backing_services).and_return({ "postgresql" => backing_service })
    end

    it "includes environment variables from the current containers configuration" do
      subject.config = { "environment" => { "rails_env" => "test" } }
      expect(subject.environment_variables).to include("RAILS_ENV")
      expect(subject.environment_variables["RAILS_ENV"]).to eq("test")
    end

    it "includes variables for the backing service provided in the local configuration" do
      expect(subject.environment_variables).to include("POSTGRESQL_DATABASE")
      expect(subject.environment_variables["POSTGRESQL_DATABASE"]).to eq("dockistrano_development")
    end

    it "includes environment variables from each backing service" do
      expect(backing_service).to receive(:provided_environment_variables).and_return({ "SUB_ENV" => "some_value" })
      expect(subject.environment_variables["SUB_ENV"]).to eq("some_value")
    end

    it "interpolates environment variables with present values" do
      expect(subject.environment_variables["DATABASE_URL"]).to eq("postgres://postgres@172.0.0.1/dockistrano_development")
    end

    it "leaves variables in tact that could not be replaced" do
      subject.config = { "environment" => { "rails_env" => "test$FOOBAR" } }
      expect(subject.environment_variables["RAILS_ENV"]).to eq("test$FOOBAR")
    end
  end

  context "#provided_environment_variables" do

    it "includes environment variables that are provided by the service" do
      expect(subject).to receive(:provides_env).and_return({ "BUNDLE_PATH" => "/bundle" })
      expect(subject.provided_environment_variables["BUNDLE_PATH"]).to eq("/bundle")
    end

  end

  context "#volumes" do
    it "includes a default data volume" do
      expect(subject.volumes).to include("/dockistrano/image/data:/dockistrano/data")
    end

    it "includes a source mount when configured" do
      allow(subject).to receive(:mount_src).and_return({ "/home/vagrant/src/app2" => "/home/app" })
      expect(subject.volumes).to include("/home/vagrant/src/app2:/home/app")
    end
  end

  context "#directories_required_on_host"

  context "#available_tags_in_registry" do
    it "returns a list of available tags for the current service" do
      expect(subject).to receive(:registry_instance).and_return(registry = double)
      expect(registry).to receive(:tags_for_image).with(subject.image_name).and_return(["develop", "master"])
      expect(subject.available_tags_in_registry).to eq(["develop", "master"])
    end

    it "returns an empty list when the repository is not found in the registry" do
      expect(subject).to receive(:registry_instance).and_return(registry = double)
      expect(registry).to receive(:tags_for_image).with(subject.image_name).and_raise(Dockistrano::Registry::RepositoryNotFoundInRegistry)
      expect(subject.available_tags_in_registry).to eq([])
    end
  end

  context "#available_tags_local" do
    it "returns a list of available tags for the current service" do
      expect(Dockistrano::Docker).to receive(:tags_for_image).with("#{subject.registry}/#{subject.image_name}").and_return(["develop", "master"])
      expect(subject.available_tags_local).to eq(["develop", "master"])
    end
  end

  context "#tag_with_fallback" do
    it "uses the feature branch when available" do
      allow(subject).to receive(:tag).and_return("feature_branch")
      allow(subject).to receive(:available_tags_local).and_return(["develop", "master", "feature_branch"])
      expect(subject.tag_with_fallback).to eq("feature_branch")
    end

    it "uses the develop branch when available" do
      allow(subject).to receive(:tag).and_return("feature_branch")
      allow(subject).to receive(:available_tags_local).and_return(["develop", "master", "latest"])
      expect(subject.tag_with_fallback).to eq("develop")
    end

    it "uses the master branch when available" do
      allow(subject).to receive(:tag).and_return("feature_branch")
      allow(subject).to receive(:available_tags_local).and_return(["master", "latest"])
      expect(subject.tag_with_fallback).to eq("master")
    end

    it "uses the latest branch when available" do
      allow(subject).to receive(:tag).and_return("feature_branch")
      allow(subject).to receive(:available_tags_local).and_return(["latest"])
      expect(subject.tag_with_fallback).to eq("latest")
    end

    it "raises an error when no tags are found" do
      allow(subject).to receive(:tag).and_return("feature_branch")
      allow(subject).to receive(:available_tags_local).and_return(["foobar", "test"])
      expect { subject.tag_with_fallback }.to raise_error(Dockistrano::Service::NoTagFoundForImage)
    end
  end

  context "#ip_address" do
    it "returns the ip address of the running container" do
      allow(subject).to receive(:running?).and_return(true)
      allow(subject).to receive(:container_settings).and_return({
        "NetworkSettings" => {
          "IPAddress" => "172.168.1.1"
        }
      })
      expect(subject.ip_address).to eq("172.168.1.1")
    end
  end

  context "#ports" do
    it "returns a string representation of the port mappings" do
      subject.config = { "ports" => [ "1234:5678" ] }
      expect(subject.ports).to eq(["1234:5678"])
    end

    it "returns the ip address included in the configuration" do
      subject.config = { "ports" => [ "33.33.33.10:1234:5678" ] }
      expect(subject.ports).to eq(["33.33.33.10:1234:5678"])
    end
  end

  context "#attach" do
    it "attaches to the output of the container" do
      expect(Dockistrano::Docker).to receive(:attach).with(subject.image_name)
      subject.attach
    end

    it "attaches to the output of the container when additional command given" do
      expect(Dockistrano::Docker).to receive(:attach).with("#{subject.image_name}_worker")
      subject.attach("worker")
    end
  end

  context "#logs" do
    it "returns the logs of the last run of the container" do
      expect(Dockistrano::Docker).to receive(:logs).with(subject.image_name)
      subject.logs
    end

    it "returns the logs of the last run of the container when additional command given" do
      expect(Dockistrano::Docker).to receive(:logs).with("#{subject.image_name}_worker")
      subject.logs("worker")
    end
  end

  context "#create_data_directories" do
    it "creates directories in the mounted data folder" do
      allow(subject).to receive(:full_image_name_with_fallback).and_return("image:develop")
      allow(subject).to receive(:data_directories).and_return(["logs"])
      allow(subject).to receive(:volumes).and_return(volumes = double)
      allow(subject).to receive(:environment_variables).and_return(environment_variables = double)
      allow(Dockistrano::Docker).to receive(:inspect_image).with(subject.full_image_name_with_fallback).and_return({ "container_config" => { "User" => "app" }})

      expect(Dockistrano::Docker).to receive(:run).with(subject.full_image_name_with_fallback,
        v: volumes,
        e: environment_variables,
        u: "root",
        rm: true,
        command: "/bin/bash -c 'mkdir -p /dockistrano/data/logs; chown app:app /dockistrano/data/logs'"
      )

      subject.create_data_directories
    end
  end

  context "#newer_version_available?" do
    let(:registry_instance) { double }

    before do
      allow(subject).to receive(:registry_instance).and_return(registry_instance)
      allow(subject).to receive(:tag_with_fallback).and_return("develop")
    end

    it "returns true when a newer version of the image is available" do
      expect(subject).to receive(:image_id).and_return("1")
      expect(registry_instance).to receive(:latest_id_for_image).with(subject.image_name, subject.tag_with_fallback).and_return("2")
      expect(subject.newer_version_available?).to be_true
    end

    it "returns false when no registry image id is found" do
      expect(registry_instance).to receive(:latest_id_for_image).with(subject.image_name, subject.tag_with_fallback).and_return(nil)
      expect(subject.newer_version_available?).to be_false
    end

    it "returns false when the registry image id is equal to the local id" do
      expect(subject).to receive(:image_id).and_return("1")
      expect(registry_instance).to receive(:latest_id_for_image).with(subject.image_name, subject.tag_with_fallback).and_return("1")
      expect(subject.newer_version_available?).to be_false
    end
  end

end
