#! /usr/bin/env ruby

#
# Ruby script to parse a FinalDraft file (.fdx) and convert it
# into ebook formats: epub and mobi
#
require "rubygems"
require "rexml/document"
require "pathname"

class Screenplay 
    attr_reader :fdxFile
    attr :title, true
    attr :author, true

    # input: .fdx input file
    def initialize(fdxFile)
        @fdxFile=fdxFile
    end
end

#
# this class parses the fdx file
# and pass the content to the generator 
#
class FdxParser
    # input: .fdx input file
    def initialize(input)
        @input=Pathname.new(input).realpath
        @sceneCounter=0
    end

    def parse(generator)
        file = File.new( @input )
        doc = REXML::Document.new file

        doc.elements.each("FinalDraft/Content/Paragraph") { 
            |element| 
            type=element.attributes["Type"] 
            
            text = ""
            element.elements.each("Text") {
                |txt|
                text = text + txt.text
            }

            if (type == "Scene Heading")
                @sceneCounter = @sceneCounter + 1
                generator.fdx_scene_heading(text,"scene_#{@sceneCounter}",@sceneCounter)
            elsif (type == "Action") 
                generator.fdx_action(text)
            elsif (type == "Character")
                 generator.fdx_character(text)
            elsif (type == "Parenthetical")
                 generator.fdx_parenthetical(text)
            elsif (type == "Dialogue")
                 generator.fdx_dialogue(text)
            elsif (type == "Transition")
                 generator.fdx_transition(text)
            else
                puts type
            end
        }
    end
    
end

class BaseGenerator
    def cleanDirectory(directory)
        puts "Cleaning up #{directory}"
        if (File.directory?(directory))
            FileUtils.remove_dir(directory)
        end
    end


    def p(file,clazz, text)
        file.puts "<p class=\"#{clazz}\">#{text}</p>"
    end
    
    def tt(file,clazz, text)
        file.puts "<tt class=\"#{clazz}\">#{text}</tt>"
    end
    
    def a(file, name)
        file.puts "<a name=\"#{name}\"/>"
    end

end

class MobiGenerator < BaseGenerator
    def generate(screenplay,output)
        @screenplay=screenplay
        parser=FdxParser.new(@screenplay.fdxFile)
        
        outputdir="__mobi"
        cleanDirectory(outputdir)
        Dir.mkdir(outputdir)
        Dir.chdir(outputdir) do
            prepare_css
            prepare_opf
            prepare_ncx
            
            @bodyFile = File.new("body.html", "w")
            @tocFile = File.new("toc.html", "w")
            @ncxFile = File.new("root.ncx", "a")
            parser.parse(self) 
            @bodyFile.close
            @tocFile.close
        @ncxFile.puts <<-END
  </navMap>
</ncx>
END
            @ncxFile.close
        
            htmlFile = File.new("book.html", "w")
        
            htmlFile.puts "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\""
            htmlFile.puts "   \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">"
            htmlFile.puts "<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\">"
            htmlFile.puts "<head>"
            htmlFile.puts "  <link rel=\"stylesheet\" href=\"main.css\" type=\"text/css\" />"
            htmlFile.puts "  <title>#{@screenplay.title}</title>"
            htmlFile.puts "  <meta http-equiv=\"Content-Type\" content=\"application/xhtml+xml; charset=utf-8\" />"
            htmlFile.puts "</head>"
            htmlFile.puts "<body>"
            htmlFile.puts "<div class=\"document\">"
            htmlFile.puts "<a name=\"title\"/>"
            htmlFile.puts "<h1 weight=\"50\" class=\"center\">#{@screenplay.title}</h1>"
            htmlFile.puts "<h3 class=\"right\">#{@screenplay.author}</h3>"
            htmlFile.puts "<mbp:pagebreak/>"
            htmlFile.puts "<a name=\"TOC\"/>"
            htmlFile.puts "<h2>Scenes</h2>"
        
            File.open('toc.html', 'r') do |f|  
                f.each do |line|
                    htmlFile.puts line
                end
            end  
            
            htmlFile.puts "<a name=\"start\"/>"
            htmlFile.puts "<a name=\"section\"/>"
            htmlFile.puts "<mbp:pagebreak/>"

        
            File.open('body.html', 'r') do |f|  
                f.each do |line|
                    htmlFile.puts line
                end
            end  
            
            htmlFile.puts "</div>"
            htmlFile.puts "</body>"
            htmlFile.puts "</html>"
            htmlFile.close
        end
    end

    def fdx_scene_heading(text,sceneId,sceneCounter)
        a(@bodyFile,sceneId)
        p(@bodyFile,"sceneheading", text)
        
        @tocFile.puts "<p width=\"-30\" style=\"text-align: left;\"><a href=\"##{sceneId}\">#{text}</a></p>"
        @ncxFile.puts <<-END
    <navPoint id="#{sceneId}" playOrder="#{sceneCounter}">
      <navLabel>
        <text>#{text}</text>
      </navLabel>
      <content src="book.html##{sceneId}"/>
    </navPoint>
END
    end

    def fdx_action(text)
        p(@bodyFile,"action", text)
    end

    def fdx_character(text)
        p(@bodyFile,"character", text)
    end

    def fdx_parenthetical(text)
        p(@bodyFile,"parenthetical", text)
    end

    def fdx_dialogue(text)
        p(@bodyFile,"dialogue", text)
    end

    def fdx_transition(text)
        p(@bodyFile,"transition", text)
    end
    
    def prepare_css
        File.open('main.css','w') do |f|
            f.puts <<-'ENDTEXT'
body {
  font-family: "Courier New", Monospace;
}

p.character {
  text-indent: 0em;
  text-align: center;
  margin-top: 10px;
}

p.parenthetical {
  margin-left: 50px; 
  text-indent: 0em;
  font-style: italic;
}

p.dialogue {
  margin-left: 50px; 
  text-indent: 0em;
}

p.sceneheading: {
  margin-top: 10px;
  text-indent: 0em;
}

p.action {
  text-indent: 0em;
  margin-top: 10px;
}
            ENDTEXT
        end 
    end
    
    def prepare_opf
        t = Time.now
    
        File.open('ebook.opf','w') do |f|
            f.puts <<-HERE
<?xml version="1.0" encoding="UTF-8" ?>
<package version="2.0" unique-identifier="bookId" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>#{@screenplay.title}</dc:title>
    <dc:language>en</dc:language>
    <dc:identifier opf:scheme="URI" id="bookId">#{t.strftime("%Y/%m/%d")}-XX</dc:identifier>
    <dc:creator opf:role="aut">#{@screenplay.author}</dc:creator>
    <dc:publisher>@ebookineur</dc:publisher>
    <dc:date opf:event="publication">#{t.strftime("%Y/%m/%d")}</dc:date>
    <dc:description>Book generated by @ebookineur</dc:description>
    <meta name="cover" content="id-cover-image"/>
  </metadata>
  <manifest>
    <item id="id-cover-image" href="cover.jpg" media-type="image/jpeg"/>
    <item id="ncx" href="root.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="css-main" href="main.css" media-type="text/css"/>
    <item id="book" href="book.html" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx"/>
  <guide>
    <reference type="title-page" title="Title Page" href="book.html#title"/>
    <reference type="toc" title="Table of Content" href="book.html#TOC"/>
  </guide>
</package>
            
HERE
        end
    end
    
    
    def prepare_ncx
        t = Time.now
    
        File.open('root.ncx','w') do |f|
            f.puts <<-HERE
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN"
"http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">

<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="en-us">
  <head>
    <meta name="dtb:uid" content="#{t.strftime("%Y/%m/%d")}-XX"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>#{@screenplay.title}</text>
  </docTitle>
  <docAuthor>
    <text>#{@screenplay.author}</text>
  </docAuthor>
  <navMap>
    <navPoint class="titlePage" id="title" playOrder="0">
      <navLabel>
        <text>Title Page</text>
      </navLabel>
      <content src="book.html#title"/>
    </navPoint>

HERE
        end
    end
end

screenplay=Screenplay.new("../TheSixthSense.fdx")
screenplay.title="The Sixth Sense"
screenplay.author="M. Night Shyamalan"

generator=MobiGenerator.new
generator.generate(screenplay,"ebook_mobi.html")

