require 'spec_helper'
require 'extensions/object'
require 'mock_response'

describe Mirage::MockResponse do
  include Mirage
  before :each do
    MockResponse.delete_all
  end

  def convert_keys_to_strings hash
    JSON.parse(hash.to_json)
  end

  describe 'initialisation' do
    it 'should find binary data' do
        string="string"
        response_spec = convert_keys_to_strings({:response => {:body => string}})
        BinaryDataChecker.should_receive(:contains_binary_data?).with(string).and_return(true)
        MockResponse.new("greeting", response_spec).binary?.should == true
    end

    it 'should not find binary data' do
      string="string"
      response_spec = convert_keys_to_strings({:response => {:body => string}})
      BinaryDataChecker.should_receive(:contains_binary_data?).with(string).and_return(false)
      MockResponse.new("greeting", response_spec).binary?.should == false
    end
  end

  describe 'saving state' do
    it 'should store the current set of responses' do
      greeting = MockResponse.new("greeting")
      farewell = MockResponse.new("farewell")

      MockResponse.backup
      MockResponse.new("farewell", "cheerio")
      MockResponse.revert

      MockResponse.all.should == [greeting, farewell]
    end
  end

  describe "response values" do

    it 'should return the response value' do
      response_spec = convert_keys_to_strings({:response => {:body => Base64.encode64("hello")}})
      MockResponse.new("greeting", response_spec).value.should == "hello"
    end

    it 'should return if the value contains binary data' do
      response_spec = convert_keys_to_strings({:response => {:body => Base64.encode64("hello ${name}")}})
      BinaryDataChecker.should_receive(:contains_binary_data?).and_return(true)
      response = MockResponse.new("greeting", response_spec)

      response.value("", {"name" => "leon"}).should == "hello ${name}"
    end

    it 'should replace patterns with values found in request parameters' do
      response_spec = convert_keys_to_strings({:response => {:body => Base64.encode64("hello ${name}")}})
      MockResponse.new("greeting", response_spec).value("", {"name" => "leon"}).should == "hello leon"
    end

    it 'should base64 decode values' do
      response_spec = convert_keys_to_strings({:response => {:body => "encoded value"}})
      Base64.should_receive(:decode64).and_return("decoded value")
      MockResponse.new("greeting", response_spec).value("")
    end

    it 'should replace patterns with values found in the body' do
      response_spec = convert_keys_to_strings({:response => {:body => Base64.encode64("hello ${name>(.*?)<}")}})
      MockResponse.new("greeting", response_spec).value("<name>leon</name>").should == "hello leon"
    end
  end

  describe "Matching http method" do
    it 'should find the response with the correct http method' do
      response_spec = convert_keys_to_strings({:request => {:http_method => "post"}})
      response = MockResponse.new("greeting", response_spec)

      MockResponse.find("", {}, "greeting", "post").should == response
      expect { MockResponse.find("", {}, "greeting", "get") }.to raise_error(ServerResponseNotFound)
    end
  end

  describe 'Finding by id' do
    it 'should find a response given its id' do
      response1 = MockResponse.new("greeting", "hello")
      MockResponse.new("farewell", "goodbye")
      MockResponse.find_by_id(response1.response_id).should == response1
    end
  end

  describe 'deleting' do

    it 'should delete a response given its id' do
      response1 = MockResponse.new("greeting", "hello")
      MockResponse.delete(response1.response_id)
      expect { MockResponse.find_by_id(response1.response_id) }.to raise_error(ServerResponseNotFound)
    end

    it 'should delete all responses' do
      MockResponse.new("greeting", "hello")
      MockResponse.new("farewell", "goodbye")
      MockResponse.delete_all
      MockResponse.all.size.should == 0
    end

  end

  describe "matching on request parameters" do
    it 'should find the response if all required parameters are present' do
      get_spec = convert_keys_to_strings(
          {
              :request => {
                  :http_method => "get",
                  :parameters => {
                      :firstname => "leon"
                  }
              },
              :response => {
                  :body => Base64.encode64("get response")
              }
          }
      )

      post_spec = convert_keys_to_strings(
          {
              :request => {
                  :http_method => "post",
                  :parameters => {
                      :firstname => "leon"
                  }
              },
              :response => {
                  :body => Base64.encode64("post response")
              }
          }
      )
      get_response = MockResponse.new("greeting", get_spec)
      post_response = MockResponse.new("greeting", post_spec)

      MockResponse.find("", {:firstname => "leon"}, "greeting", "post").should == post_response
      MockResponse.find("", {:firstname => "leon"}, "greeting", "get").should == get_response
    end

    it 'should match request parameter values using regexps' do
      response_spec = convert_keys_to_strings(
          {
              :request => {
                  :parameters => {:firstname => "%r{leon.*}"}
              },
              :response => {
                  :body => 'response'
              }

          }
      )
      response = MockResponse.new("greeting", response_spec)

      MockResponse.find("", {:firstname => "leon"}, "greeting", "get").should == response
      MockResponse.find("", {:firstname => "leonard"}, "greeting", "get").should == response
      expect { MockResponse.find("", {:firstname => "leo"}, "greeting", "get") }.to raise_error(ServerResponseNotFound)
    end
  end

  describe 'matching against the request body' do
    it 'should match required fragments in the request body' do

      response_spec = convert_keys_to_strings(
          {
              :request => {
                  :body_content => %w(leon)
              },
              :response => {
                  :body => 'response'
              }

          }
      )

      response = MockResponse.new("greeting", response_spec)
      MockResponse.find("<name>leon</name>", {}, "greeting", "get").should == response
      expect { MockResponse.find("<name>jeff</name>", {}, "greeting", "get") }.to raise_error(ServerResponseNotFound)
    end

    it 'should use regexs to match required fragements in the request body' do
      response_spec = convert_keys_to_strings(
          {
              :request => {
                  :body_content => %w(%r{leon.*})
              },
              :response => {
                  :body => 'response'
              }

          }
      )

      response = MockResponse.new("greeting", response_spec)
      MockResponse.find("<name>leon</name>", {}, "greeting", "get").should == response
      MockResponse.find("<name>leonard</name>", {}, "greeting", "get").should == response
      expect { MockResponse.find("<name>jef</name>", {}, "greeting", "get") }.to raise_error(ServerResponseNotFound)
    end
  end

  it 'should be equal to another response that is the same not including the response value' do

    spec = convert_keys_to_strings({:response => {:body => "hello1",
                                                  :content_type => "text/xml",
                                                  :status => 202,
                                                  :delay => 1.0,
                                                  :default => true,
                                                  :file => false}

                                   })

    response = MockResponse.new("greeting", spec)
    response.should_not == MockResponse.new("greeting", {})
    response.should == MockResponse.new("greeting", spec)
  end

  describe "scoring to represent the specificity of a response" do

    it 'should score an exact requirement match at 2' do
      response_spec = convert_keys_to_strings(
          {
              :request => {
                  :parameters => {:firstname => "leon"}
              },
              :response => {
                  :body => 'response'
              }

          }
      )
      MockResponse.new("greeting", response_spec).score.should == 2

      response_spec = convert_keys_to_strings(
          {
              :request => {
                  :body_content => %w(login)
              },
              :response => {
                  :body => 'response'
              }

          }
      )
      MockResponse.new("greeting", response_spec).score.should == 2
    end

    it 'should score a match found by regexp at 1' do

      response_spec = convert_keys_to_strings(
          {
              :request => {
                  :parameters => {:firstname => "%r{leon.*}"}
              },
              :response => {
                  :body => 'response'
              }

          }
      )
      MockResponse.new("greeting", response_spec).score.should == 1

      response_spec = convert_keys_to_strings(
          {
              :request => {
                  :body_content => %w(%r{input|output})
              },
              :response => {
                  :body => 'response'
              }

          }
      )
      MockResponse.new("greeting", response_spec).score.should == 1
    end

    it 'should find the most specific response' do
      default_response_spec = convert_keys_to_strings(
          {
              :request => {
                  :body_content => %w(login)
              },
              :response => {
                  :body => 'default_response'
              }

          }
      )

      specific_response_spec = convert_keys_to_strings(
          {
              :request => {
                  :body_content => %w(login),
                  :parameters => {
                      :name => "leon"
                  }
              },
              :response => {
                  :body => 'specific response'
              }

          }
      )

      MockResponse.new("greeting", default_response_spec)
      expected_response = MockResponse.new("greeting", specific_response_spec)
      MockResponse.find("<action>login</action>", {:name => "leon"}, "greeting", "get").should == expected_response
    end
  end


  it 'should all matching to be based on body content, request parameters and http method' do
    response_spec = convert_keys_to_strings({
                                                :request => {
                                                    :body_content => %w(login),
                                                    :parameters => {
                                                        :name => "leon"
                                                    },
                                                    :http_method => "post"
                                                },
                                                :response => {
                                                    :body => "response"
                                                }
                                            })


    response = MockResponse.new("greeting", response_spec)
    MockResponse.find("<action>login</action>", {:name => "leon"}, "greeting", "post").should == response
    expect { MockResponse.find("<action>login</action>", {:name => "leon"}, "greeting", "get") }.to raise_error(ServerResponseNotFound)
  end

  it 'should recycle response ids' do
    response_spec = convert_keys_to_strings({
                                                :request => {
                                                    :body_content => %w(login),
                                                    :parameters => {
                                                        :name => "leon"
                                                    },
                                                    :http_method => "post"
                                                },
                                                :response => {
                                                    :body => "response"
                                                }
                                            })
    response1 = MockResponse.new("greeting", response_spec)
    response2 = MockResponse.new("greeting", response_spec)

    response1.response_id.should_not == nil
    response1.response_id.should == response2.response_id
  end

  it 'should raise an exception when a response is not found' do
    expect { MockResponse.find("<action>login</action>", {:name => "leon"}, "greeting", "post") }.to raise_error(ServerResponseNotFound)
  end

  it 'should return all responses' do
    MockResponse.new("greeting", convert_keys_to_strings({:response => {:body => "hello"}}))
    MockResponse.new("greeting", convert_keys_to_strings({:request => {:body_content => %w(leon)}, :response => {:body => "hello leon"}}))
    MockResponse.new("greeting", convert_keys_to_strings({:request => {:body_content => %w(leon), :http_method => "post"}, :response => {:body => "hello leon"}}))
    MockResponse.new("deposit", convert_keys_to_strings({:request => {:body_content => %w(amount), :http_method => "post"}, :response => {:body => "received"}}))
    MockResponse.all.size.should == 4
  end

  describe 'finding defaults' do
    it 'most appropriate response under parent resource and same http method' do
      level1_response = MockResponse.new("level1", convert_keys_to_strings({:response => {:body => "level1", :default => true}}))
      MockResponse.new("level1/level2", convert_keys_to_strings({:response => {:body => "level2", :default => true}, :request => {:body_content => %w(body)}}))
      MockResponse.find_default("", "get", "level1/level2/level3", {}).should == level1_response
    end
  end

  it 'should generate subdomains' do
    MockResponse.subdomains("1/2/3").should == ["1/2/3", '1/2', '1']
  end

  it 'should generate a json representation of itself' do
    response_spec = convert_keys_to_strings({
                                                :request => {
                                                    :body_content => %w(login),
                                                    :parameters => {
                                                        :name => "leon"
                                                    },
                                                    :http_method => "post"
                                                },
                                                :response => {
                                                    :body => "response",
                                                    :delay => 0,
                                                    :content_type => 'text/plain',
                                                    :status => 200,
                                                    :default => false
                                                }
                                            })
    JSON.parse(MockResponse.new("greeting",response_spec).raw).should == response_spec
  end

end