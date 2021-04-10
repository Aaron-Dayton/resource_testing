# Parse an HTML file and generate a TOC from it
require 'nokogiri'
require 'haml'
class Html2Toc
  attr_reader :sections, :parsed, :toc_level, :make_links, :link_file_name

  # parsed_html is a Nokogiri::HTML object. Get it like this: Nokogiri::HTML(html_content)
  # Levels are h1,    h2,       h3,       h4,           h5,
  #            parts, chapters, sections, sub-sections, sub-sub-sections
  def initialize(content_data, params = {})
    @toc_level = params[:toc_level] || 3
    @link_file_name = params[:link_file_name]
    @make_links = params[:make_links]
    @content_data = content_data
    @container_xpath = params[:container_xpath]
    @list_type = params[:list_type] || 'ul'
    @input_format = params[:input_format] || 'kramdown'
    @toc_level -= 1 if @input_format == 'markua'
    @toc_level = 0 if @toc_level < 0
    find_sections
  end

  def to_html
    Haml::Engine.new(to_haml).render
  end

  def has_parts?
    selector = if @input_format == 'kramdown'
                 '//h1'
               else
                 '//h1[@class = "part"]'
               end
    !@content_data.all? { |data| data[:content].xpath(selector).empty? }
  end

  private

  def to_haml
    haml = "%#{@list_type}.toc#{has_parts? ? '.has-parts' : '.no-parts'}\n"
    last_level = 1
    is_first = true
    haml += @sections.map do |section_data|
      section = section_data[:section]

      # Links inside links give you EPUB validation errors
      # and we put the title inside of a link in the ToC
      section.css('a').each {|a| a.replace(a.content)}

      link_file_name = section_data[:link_file_name]

      section.name =~ /h(\d)/
      level = Regexp.last_match(1).to_i
      level -= 1 if @input_format != 'markua' && !has_parts?
      if @input_format == 'markua'
        level += 1 if has_parts? && section.attr('class') != 'part'
      end

      level_diff = level - last_level
      last_level = level
      res = ''

      res << "  %li\n    %span &#160;\n" if level_diff > 0 && is_first

      # Stick in an extra <li><ul> for every level you jump
      first_diff = true
      while level_diff > 0
        lev = level - level_diff
        li_indent = ' ' * (lev * 4 - 2)
        ul_indent = ' ' * (lev * 4)
        res << "#{li_indent}%li\n" unless first_diff
        res << "#{ul_indent}%span &#160;\n" unless first_diff
        res << "#{ul_indent}%#{@list_type}\n"
        first_diff = false
        level_diff -= 1
      end

      li_indent = ' ' * (level * 4 - 2)
      text_indent = ' ' * (level * 4)

      section.search('img').remove # No need for images in the ToC
      section.search('sup').remove # Don't include footnote numbers in the ToC
      text = section.children.to_xml.split(/\n/).join('').gsub(/#\{/, '#\\{').gsub(/^#/, '\#')
      if make_links
        href = "#{link_file_name if link_file_name}##{section['id']}"
        text = "%a{:href => '#{href}'} " + text
      else
        # Don't blow up for titles starting with - or : or .
        text = text.gsub(/^-/, '\\-').gsub(/^\:/, '\\:').gsub(/^\./, '\\.')
      end

      is_first = false
      res << "#{li_indent}%li\n#{text_indent}#{text}"
      res
    end.join("\n")
  end

  def find_sections
    if @toc_level == 0
      @sections = []
      return
    end

    xpath_string = @container_xpath ? @container_xpath : ''
    xpath_string << '//*[' + (1..toc_level).map { |level| "self::h#{level}" }.join(' or ') + ']'
    @sections = @content_data.map do |data|
      data[:content].xpath(xpath_string).reject do |el|
        el.ancestors.any? do |parent|
          is_blockquote = parent.name == 'blockquote'
          is_blurb_or_aside = parent.name == 'aside'
          is_endnotes = parent.attr('class') == 'footnotes'
          is_blockquote || is_blurb_or_aside || is_endnotes
        end
      end.map do |section|
        { section: section, link_file_name: data[:link_file_name] }
      end
    end.flatten
  end
end
