require 'spec_helper'

describe Dockistrano::Registry do

  subject { described_class.new("registry.dev") }

  context "#tags_for_image" do
    it "returns all available tags on the registry" do
      stub_request(:get, "http://registry.dev/v1/repositories/image_name/tags").to_return({
        status: 200,
        body: '{"develop": "49f387cc90f2d5b82ded91c239b6e583f8b955cb532912cc959b1d1289b3f8f1"}'
      })

      expect(subject.tags_for_image("image_name")).to eq({
        "develop" => "49f387cc90f2d5b82ded91c239b6e583f8b955cb532912cc959b1d1289b3f8f1"
      })
    end

    it "raises an error when the repository is not found in the registry" do
      stub_request(:get, "http://registry.dev/v1/repositories/foobar/tags").to_return({
        status: 404,
        body: '{"error": "Repository not found"}'
      })
      expect { subject.tags_for_image("foobar") }.to raise_error(Dockistrano::Registry::RepositoryNotFoundInRegistry)
    end

    it "raises an error when the request failed" do
      stub_request(:get, "http://registry.dev/v1/repositories/foobar/tags").to_return({
        status: 500,
        body: '{"error": "Something else"}'
      })
      expect { subject.tags_for_image("foobar") }.to raise_error("Something else")
    end
  end

  context "#latest_id_for_image" do
    it "returns the id for the image in the registry" do
      stub_request(:get, "http://registry.dev/v1/repositories/foobar/tags/develop").to_return({
        status: 200,
        body: '"49f387cc90f2d5b82ded91c239b6e583f8b955cb532912cc959b1d1289b3f8f1"'
      })

      expect(subject.latest_id_for_image("foobar", "develop")).to eq("49f387cc90f2d5b82ded91c239b6e583f8b955cb532912cc959b1d1289b3f8f1")
    end

    it "returns nil when the image is not available in the registry" do
      stub_request(:get, "http://registry.dev/v1/repositories/foobar/tags/develop").to_return({
        status: 404,
        body: '{"error": "Tag not found"}'
      })

      expect(subject.latest_id_for_image("foobar", "develop")).to be_nil
    end
  end

end
