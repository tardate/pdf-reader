# coding: utf-8

require File.dirname(__FILE__) + "/spec_helper"

describe PDF::Reader::FileWriter, "to_s method" do
  it "should return a string the begins with the PDF marker when working on an empty ObjectHash" do
    h  = PDF::Reader::ObjectHash.new
    fw = PDF::Reader::FileWriter.new(h)

    fw.to_s[0,8].should == "%PDF-1.3"
  end

  it "should return a string that ends with the EOF marker when working on an empty ObjectHash" do
    h  = PDF::Reader::ObjectHash.new
    fw = PDF::Reader::FileWriter.new(h)

    fw.to_s[-6,6].should == "%%EOF\n"
    File.open("foo.pdf", "wb") { |f| f.write fw.to_s }
  end

  it "should return a string that ends with the EOF marker when working on an empty ObjectHash" do
    h  = PDF::Reader::ObjectHash.new
    fw = PDF::Reader::FileWriter.new(h)

    fw.to_s[-6,6].should == "%%EOF\n"
    File.open("foo.pdf", "wb") { |f| f.write fw.to_s }
  end
end
