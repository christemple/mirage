require 'spec_helper'

describe Helpers::MethodBuilder do
  it 'should give a builder_method builder method' do
    model_class = Class.new do
      extend Helpers::MethodBuilder

      builder_method :name
      builder_method :age
    end
    name, age = 'Joe', 25

    person = model_class.new
    person.name(name).age(age)
    person.name.should == name
    person.age.should == age
  end

  it 'should let you define more than one builder method at a time' do
    model_class = Class.new do
      extend Helpers::MethodBuilder

      builder_methods :name, :age
    end
    name, age = 'Joe', 25

    person = model_class.new
    person.name(name).age(age)
    person.name.should == name
    person.age.should == age
  end
end