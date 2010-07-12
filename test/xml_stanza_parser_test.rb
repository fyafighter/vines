include Vines

class XmlStanzaParserTest < Test::Unit::TestCase

  def setup
  end

  def teardown
  end

  def test_simple_stanza
    xml = '<t></t>'
    parser = XmlStanzaParser.new
    stanzas = parser.stanzas(xml)
    assert_equal(1, stanzas.length)
    assert_equal(xml, stanzas.first)
  end

  def test_simple_stanza2
    xml = '<tag></tag>'
    parser = XmlStanzaParser.new
    stanzas = parser.stanzas(xml)
    assert_equal(1, stanzas.length)
    assert_equal(xml, stanzas.first)
  end

  def test_simple_attribute
    xml = '<tag a="v"></tag>'
    parser = XmlStanzaParser.new
    stanzas = parser.stanzas(xml)
    assert_equal(1, stanzas.length)
    assert_equal(xml, stanzas.first)
  end

  def test_simple_attributes
    xml = '<tag attr1="value1" attr2="value2"></tag>'
    parser = XmlStanzaParser.new
    stanzas = parser.stanzas(xml)
    assert_equal(1, stanzas.length)
    assert_equal(xml, stanzas.first)
  end

  def test_cdata_attributes
    xml = '<tag attr1="value1" attr2="<![CDATA[[ value2 ]]>"></tag>'
    parser = XmlStanzaParser.new
    stanzas = parser.stanzas(xml)
    assert_equal(1, stanzas.length)
    assert_equal(xml, stanzas.first)
  end

  def test_body_msg
    xml = '<tag attr1="value1" attr2="<![CDATA[[ value2 ]]>"> body </tag>'
    parser = XmlStanzaParser.new
    stanzas = parser.stanzas(xml)
    assert_equal(1, stanzas.length)
    assert_equal(xml, stanzas.first)
  end

  def test_body_comment
    xml = '<tag attr1="value1" attr2="<![CDATA[[ value2 ]]>"><!-- comment -->body</tag>'
    parser = XmlStanzaParser.new
    stanzas = parser.stanzas(xml)
    assert_equal(1, stanzas.length)
    assert_equal(xml, stanzas.first)
  end

  def test_body_cdata
    xml = '<tag attr1="value1" attr2="<![CDATA[[ value2 ]]>"><![CDATA[[ <test></tag> ]]></tag>'
    parser = XmlStanzaParser.new
    stanzas = parser.stanzas(xml)
    assert_equal(1, stanzas.length)
    assert_equal(xml, stanzas.first)
  end

  def test_multiple_stanzas
    one = %q{
      <tag attr1="value1" attr2="<![CDATA[[ value2 ]]>">
        <![CDATA[[ <test></tag> ]]>
      </tag>
    }
    two = %q{
      <tag2>
        <pre>text
             line 2
        </pre>
      </tag2> 
    }
    parser = XmlStanzaParser.new
    stanzas = parser.stanzas(one + two)
    assert_equal(2, stanzas.length)
    assert_equal(one.strip, stanzas.first)
    assert_equal(two.strip, stanzas[1])
  end

  def test_worst_case_partial_stanzas
    one = %q{
      <tag attr1="value1" attr2="<![CDATA[[ value2 ]]>">
        <![CDATA[[ <test></tag> ]]>
      </tag>
    }
    two = %q{
      <tag2>
        <pre>text
             line 2
        </pre>
      </tag2> 
    }
    parser = XmlStanzaParser.new
    stanzas = []
    # worst case scenario: incoming data is one character at a time
    (one + two).split(//).each do |ch|
      stanzas += parser.stanzas(ch)
    end
    assert_equal(2, stanzas.length)
    assert_equal(one.strip, stanzas.first)
    assert_equal(two.strip, stanzas[1])
  end

  def test_partial_stanzas
    full = ["<chunk1><sub1>test1</sub1></chunk1>",
            "<chunk2><sub2> test 2 </sub2><![CDATA[ </chunk2> ]]><!-- </chunk2> --></chunk2>"]

    chunks = ["<chunk1><sub1>test1</sub1></chu",
              "nk1><chunk2><sub2> test 2 </sub",
              "2><![CDATA[ </chunk2> ]]><!-- </chunk2> ",
              "--></chunk2>"]
    parser = XmlStanzaParser.new
    stanzas = []
    chunks.each do |c|
      stanzas += parser.stanzas(c)
    end
    assert_equal(2, stanzas.length)
    assert_equal(full[0], stanzas[0])
    assert_equal(full[1], stanzas[1])
  end

  def test_minimum_stanzas
    xml = "<a></a><b></b><c></c>"
    @parser = XmlStanzaParser.new
    stanzas = @parser.stanzas(xml)
    assert_equal(3, stanzas.length)
    assert_equal("<a></a>", stanzas[0])
    assert_equal("<b></b>", stanzas[1])
    assert_equal("<c></c>", stanzas[2])
  end

  def test_base64_stanza
    xml = "<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='EXTERNAL'>dmVyb25hLmxpdA==</auth>"
    @parser = XmlStanzaParser.new
    stanzas = @parser.stanzas(xml)
    assert_equal(1, stanzas.length)
    assert_equal(xml, stanzas[0])
  end

  def test_default_max_buffer_size
    parser = XmlStanzaParser.new
    assert_raise RuntimeError do
      parser.stanzas(("t" * 1024 * 1024) + 'o')
    end
  end

  def test_custom_max_buffer_size
    parser = XmlStanzaParser.new(1)
    assert_raise RuntimeError do
      parser.stanzas("<t")
    end
  end

end
