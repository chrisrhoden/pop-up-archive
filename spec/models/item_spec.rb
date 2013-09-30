require 'spec_helper'

describe Item do
  before { StripeMock.start }
  after { StripeMock.stop }
  context "#geographic_location" do
    it "should set the geolocation using Geoloation.for_name" do
      Geolocation.should_receive(:for_name).with("Cambridge, MA")
      FactoryGirl.build :item, geographic_location: "Cambridge, MA"
    end

    it "should return the string name of the associated geolocation" do
      record = FactoryGirl.create :item, geographic_location: "Madison, WI"

      record.geographic_location.should eq "Madison, WI"
    end
  end

  it "should allow writing to the extra attributes" do
    item = FactoryGirl.build :item
    item.extra['testkey'] = 'test value'
    item.save
  end

  it 'should persist the extra attributes' do
    item = FactoryGirl.create :item
    item.extra['testKey'] = 'testValue2'
    item.save

    Item.find(item.id).extra['testKey'].should eq 'testValue2'
  end

  it "should create a unique token fromthe title and keep it" do
    item = FactoryGirl.build :item
    item.title = 'test'
    item.token.should start_with('test.')
    item.token.should end_with('.popuparchive.org')
    item.title = 'test2'
    item.token.should start_with('test.')
  end

  it "should create entities from content analysis" do
    analysis = '{"language":"","topics":[{"name":"Business and finance","score":0.952,"original":"Business_Finance"},{"name":"Hospitality and recreation","score":0.937,"original":"Hospitality_Recreation"},{"name":"Law and crime","score":0.868,"original":"Law_Crime"},{"name":"Entertainment and culture","score":0.587,"original":"Entertainment_Culture"},{"name":"Media","score":0.742268,"original":"Media"}],"tags":[{"name":"cashola","score":0.5}],"entities":[],"relations":[],"locations":[]}'
    item = FactoryGirl.create :item
    item.process_analysis(analysis)
    item.entities.count.should eq 6
  end

  it "should not create dupe entities from content analysis" do
    analysis = '{"language":"","topics":[{"name":"Business and finance","score":0.952,"original":"Business_Finance"},{"name":"Hospitality and recreation","score":0.937,"original":"Hospitality_Recreation"},{"name":"Law and crime","score":0.868,"original":"Law_Crime"},{"name":"Entertainment and culture","score":0.587,"original":"Entertainment_Culture"},{"name":"Media","score":0.742268,"original":"Media"}],"tags":[{"name":"cashola","score":0.5}],"entities":[],"relations":[],"locations":[]}'
    item = FactoryGirl.create :item
    item.process_analysis(analysis)
    item.process_analysis(analysis)
    item.entities.count.should eq 6
  end

  it "should change visibility when collection changes" do    
    item = FactoryGirl.create :item
    item.set_defaults
    item.is_public.should == true
    collection = FactoryGirl.create :collection_private
    item.collection_id = collection.id
    item.collection = collection
    item.save!
    item.is_public.should == false
  end

end
