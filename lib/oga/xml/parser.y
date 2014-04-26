##
# DOM parser for both XML and HTML.
#
# Note that this parser itself does not deal with special HTML void elements.
# It requires every tag to have a closing tag. As such you'll need to enable
# HTML parsing mode when parsing HTML. This can be done as following:
#
#     parser = Oga::XML::Parser.new(:html => true)
#
class Oga::XML::Parser

token T_STRING T_TEXT
token T_DOCTYPE_START T_DOCTYPE_END T_DOCTYPE_TYPE T_DOCTYPE_NAME
token T_CDATA_START T_CDATA_END
token T_COMMENT_START T_COMMENT_END
token T_ELEM_START T_ELEM_NAME T_ELEM_NS T_ELEM_END T_ATTR
token T_XML_DECL_START T_XML_DECL_END

options no_result_var

rule
  document
    : expressions { create_document(val[0]) }
    | /* none */  { create_document }
    ;

  expressions
    : expressions expression { val.compact }
    | expression             { val }
    | /* none */             { [] }
    ;

  expression
    : doctype
    | cdata
    | comment
    | element
    | text
    | xmldecl
    ;

  # Doctypes

  doctype
    # <!DOCTYPE html>
    : T_DOCTYPE_START T_DOCTYPE_NAME T_DOCTYPE_END
      {
        Doctype.new(:name => val[1])
      }

    # <!DOCTYPE html PUBLIC>
    | T_DOCTYPE_START T_DOCTYPE_NAME T_DOCTYPE_TYPE T_DOCTYPE_END
      {
        Doctype.new(:name => val[1], :type => val[2])
      }

    # <!DOCTYPE html PUBLIC "foo">
    | T_DOCTYPE_START T_DOCTYPE_NAME T_DOCTYPE_TYPE T_STRING T_DOCTYPE_END
      {
        Doctype.new(:name => val[1], :type => val[2], :public_id => val[3])
      }

    # <!DOCTYPE html PUBLIC "foo" "bar">
    | T_DOCTYPE_START T_DOCTYPE_NAME T_DOCTYPE_TYPE T_STRING T_STRING T_DOCTYPE_END
      {
        Doctype.new(
          :name      => val[1],
          :type      => val[2],
          :public_id => val[3],
          :system_id => val[4]
        )
      }
    ;

  # CDATA tags

  cdata
    # <![CDATA[]]>
    : T_CDATA_START T_CDATA_END { Cdata.new }

    # <![CDATA[foo]]>
    | T_CDATA_START T_TEXT T_CDATA_END { Cdata.new(:text => val[1]) }
    ;

  # Comments

  comment
    # <!---->
    : T_COMMENT_START T_COMMENT_END { Comment.new }

    # <!-- foo -->
    | T_COMMENT_START T_TEXT T_COMMENT_END { Comment.new(:text => val[1]) }
    ;

  # Elements

  element_open
    # <p>
    : T_ELEM_START T_ELEM_NAME { [nil, val[1]] }

    # <foo:p>
    | T_ELEM_START T_ELEM_NS T_ELEM_NAME { [val[1], val[2]] }
    ;

  element
    : element_open attributes expressions T_ELEM_END
      {
        element = Element.new(
          :namespace  => val[0][0],
          :name       => val[0][1],
          :attributes => val[1]
        )

        element.children = val[2].flatten

        link_children(element)

        element
      }
    ;

  # Attributes

  attributes
    : attributes_
      {
        attrs = {}

        val[0].each do |pair|
          attrs = attrs.merge(pair)
        end

        attrs
      }
    | /* none */  { {} }
    ;

  attributes_
    : attributes_ attribute { val.flatten }
    | attribute             { val }
    ;

  attribute
    # foo
    : T_ATTR { {val[0] => nil} }

    # foo="bar"
    | T_ATTR T_STRING { {val[0] => val[1]} }
    ;

  # XML declarations
  xmldecl
    : T_XML_DECL_START T_XML_DECL_END
      {
        XmlDeclaration.new
      }
    | T_XML_DECL_START attributes T_XML_DECL_END
      {
        XmlDeclaration.new(val[1])
      }

  # Plain text

  text
    : T_TEXT { Text.new(:text => val[0]) }
    ;
end

---- inner
  ##
  # @param [String] data The input to parse.
  #
  # @param [Hash] options
  # @see Oga::XML::Lexer#initialize
  #
  def initialize(data, options = {})
    @data  = data
    @lexer = Lexer.new(data, options)
  end

  ##
  # Resets the internal state of the parser.
  #
  def reset
    @line = 1

    @lexer.reset
  end

  ##
  # Yields the next token from the lexer.
  #
  # @yieldparam [Array]
  #
  def yield_next_token
    @lexer.advance do |(type, value, line)|
      @line = line if line

      yield [type, value]
    end

    yield [false, false]
  end

  ##
  # @param [Fixnum] type The type of token the error occured on.
  # @param [String] value The value of the token.
  # @param [Array] stack The current stack of parsed nodes.
  # @raise [Racc::ParseError]
  #
  def on_error(type, value, stack)
    name  = token_to_str(type)
    index = @line - 1
    lines = @data.lines.to_a
    code  = ''

    # Show up to 5 lines before and after the offending line (if they exist).
    (-5..5).each do |offset|
      line   = lines[index + offset]
      number = @line + offset

      if line and number > 0
        if offset == 0
          prefix = '=> '
        else
          prefix = '   '
        end

        line = line.strip

        if line.length > 80
          line = line[0..79] + ' (more)'
        end

        code << "#{prefix}#{number}: #{line}\n"
      end
    end

    raise Racc::ParseError, <<-EOF.strip
Unexpected #{name} with value #{value.inspect} on line #{@line}:

#{code}
    EOF
  end

  ##
  # Parses the input and returns the corresponding AST.
  #
  # @example
  #  parser = Oga::Parser.new('<foo>bar</foo>')
  #  ast    = parser.parse
  #
  # @return [Oga::AST::Node]
  #
  def parse
    ast = yyparse(self, :yield_next_token)

    reset

    return ast
  end

  private

  ##
  # Creates a new {Oga;:XML::Document} node with the specified child elements.
  #
  # @param [Array] children
  # @return [Oga::XML::Document]
  #
  def create_document(children = [])
    if children.is_a?(Array)
      children = children.flatten
    else
      children = [children]
    end

    document = Document.new

    children.each do |child|
      if child.is_a?(Doctype)
        document.doctype = child

      elsif child.is_a?(XmlDeclaration)
        document.xml_declaration = child

      else
        document.children << child
      end
    end

    link_children(document)

    return document
  end

  ##
  # Links the child nodes together by setting attributes such as the
  # previous, next and parent node.
  #
  # @param [Oga::XML::Node] node
  #
  def link_children(node)
    amount = node.children.length

    node.children.each_with_index do |child, index|
      prev_index = index - 1
      next_index = index + 1

      if index > 0
        child.previous = node.children[prev_index]
      end

      if next_index <= amount
        child.next = node.children[next_index]
      end

      child.parent = node
    end
  end

# vim: set ft=racc:
