#
# Author:: Steven Danna (steve@opscode.com)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'spec_helper'

require 'chef/org'
require 'tempfile'

describe Chef::Org do
  before(:each) do
    @org = Chef::Org.new
  end

  describe "initialize" do
    it "should be a Chef::Org" do
      expect(@org).to be_a_kind_of(Chef::Org)
    end
  end

  describe "name" do
    it "should let you set the name to a string" do
      @org.name "sg1"
      expect(@org.name).to eq("sg1")
    end

    # It is not feasible to check all invalid characters.  Here are a few
    # that we probably care about.
    it "should not accept invalid characters" do
      # capital letters
      expect { @org.name "Bar" }.to raise_error(ArgumentError)
      # slashes
      expect { @org.name "foo/bar" }.to raise_error(ArgumentError)
      # ?
      expect { @org.name "foo?" }.to raise_error(ArgumentError)
      # &
      expect { @org.name "foo&" }.to raise_error(ArgumentError)
      # spaces
      expect { @org.name "foo&" }.to raise_error(ArgumentError)
    end

    it "should throw an ArgumentError if you feed it anything but a string" do
      expect { @org.name Hash.new }.to raise_error(ArgumentError)
    end
  end

  describe "full_name" do
    it "should let you set the full name" do
      @org.full_name "foo"
      expect(@org.full_name).to eq("foo")
    end

    it "should throw an ArgumentError if you feed it anything but a string" do
      expect { @org.name Hash.new }.to raise_error(ArgumentError)
    end
  end

  describe "private_key" do
    it "should return the private key" do
      @org.private_key("super private")
      expect(@org.private_key).to eq("super private")
    end

    it "should throw an ArgumentError if you feed it something lame" do
      expect { @org.private_key Hash.new }.to raise_error(ArgumentError)
    end
  end

  describe "when serializing to JSON" do
    before(:each) do
      @org.name("black")
      @org.full_name("black crowes")
      @json = @org.to_json
    end

    it "serializes as a JSON object" do
      expect(@json).to match(/^\{.+\}$/)
    end

    it "includes the name value" do
      expect(@json).to include(%q{"name":"black"})
    end

    it "includes the full name value" do
      expect(@json).to include(%q{"full_name":"black crowes"})
    end

    it "includes the private key when present" do
      @org.private_key("monkeypants")
      expect(@org.to_json).to include(%q{"private_key":"monkeypants"})
    end

    it "does not include the private key if not present" do
      expect(@json).to_not include("private_key")
    end
  end

  describe "when deserializing from JSON" do
    before(:each) do
      org = { "name" => "turtle",
        "full_name" => "turtle_club",
        "private_key" => "pandas" }
      @org = Chef::Org.from_json(org.to_json)
    end

    it "deserializes to a Chef::Org object" do
      expect(@org).to be_a_kind_of(Chef::Org)
    end

    it "preserves the name" do
      expect(@org.name).to eq("turtle")
    end

    it "preserves the full_name" do
      expect(@org.full_name).to eq("turtle_club")
    end

    it "includes the private key if present" do
      expect(@org.private_key).to eq("pandas")
    end
  end

  describe "API Interactions" do
    before (:each) do
      Chef::Config[:chef_server_root] = "http://www.example.com"
      @rest = double('rest')
      allow(Chef::REST).to receive(:new).and_return(@rest)
      @org = Chef::Org.new
      @org.name "foobar"
      @org.full_name "foo bar bat"
    end

    describe "list" do
      before(:each) do
        @response = {"foobar" => "http://www.example.com/organizations/foobar"}
        @inflated_response = {"foobar" => @org }
        allow(Chef::Org).to receive(:load).with("foobar").and_return(@org)
      end

      it "lists all orgs" do
        expect(@rest).to receive(:get_rest).with("organizations").and_return(@response)
        expect(Chef::Org.list).to eq(@response)
      end

      it "inflate all orgs" do
        expect(@rest).to receive(:get_rest).with("organizations").and_return(@response)
        expect(Chef::Org.list(true)).to eq(@inflated_response)
      end
    end

    describe "create" do
      it "creates a new org via the API" do
        expect(@rest).to receive(:post_rest).with("organizations", {:name => "foobar", :full_name => "foo bar bat"}).and_return({})
        @org.create
      end
    end

    describe "read" do
      it "loads a named org from the API" do
        expect(@rest).to receive(:get_rest).with("organizations/foobar").and_return({"name" => "foobar", "full_name" => "foo bar bat", "private_key" => "private"})
        org = Chef::Org.load("foobar")
        expect(org.name).to eq("foobar")
        expect(org.full_name).to eq("foo bar bat")
        expect(org.private_key).to eq("private")
      end
    end

    describe "update" do
      it "updates an existing org on via the API" do
        expect(@rest).to receive(:put_rest).with("organizations/foobar", {:name => "foobar", :full_name => "foo bar bat"}).and_return({})
        @org.update
      end
    end

    describe "destroy" do
      it "deletes the specified org via the API" do
        expect(@rest).to receive(:delete_rest).with("organizations/foobar")
        @org.destroy
      end
    end
  end
end
