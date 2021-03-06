Feature: the client can be used for peeking at responses hosted on Mirage.

  Background:
    Given the following gems are required to run the Mirage client test code:
    """
    require 'rubygems'
    require 'rspec'
    require 'mirage/client'
    """

  Scenario: peeking a response
    Given I send PUT to 'http://localhost:7001/mirage/templates/greeting' with body 'Hello'

    When I run
    """
      Mirage::Client.new.response(1).should == 'Hello'
    """

    When I send GET to 'http://localhost:7001/mirage/requests/1'
    Then a 404 should be returned

  Scenario: getting a response that does not exist
    Given I run
    """
    begin
      Mirage::Client.new.response(2).should == 'this should not have happened'
      fail("Error should have been thrown")
    rescue Exception => e
    puts e
      e.is_a?(Mirage::ResponseNotFound).should == true
    end
    """