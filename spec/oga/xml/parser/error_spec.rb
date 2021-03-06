require 'spec_helper'

describe Oga::XML::Parser do
  describe 'raising syntax errors' do
    before do
      @invalid_xml = <<-EOF.strip
<person>
  <name>Alice</name>
  <age>25
  <nationality>Dutch</nationality>
</person>
      EOF
    end

    it 'raises a LL::ParserError' do
      expect { parse(@invalid_xml) }.to raise_error(LL::ParserError)
    end

    it 'includes the line number when using a String as input' do
      parse_error(@invalid_xml).should =~ /on line 5/
    end

    it 'includes the line number when using an IO as input' do
      parse_error(StringIO.new(@invalid_xml)).should =~ /on line 5/
    end

    it 'uses more friendly error messages when available' do
      parse_error('<foo>').should ==
        'Unexpected end of input, expected element closing tag instead on line 1'
    end
  end
end
