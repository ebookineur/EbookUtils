#! /usr/bin/env ruby

#
# Ruby script to parse a FinalDraft file (.fdx) and convert it
# into ebook formats: epub and mobi
#
# sudo gem install rubyzip
#
require "rubygems"
require "rexml/document"
require "pathname"
require "zip/zip"
require "optparse"

# This hash will hold all of the options
# parsed from the command-line by
# OptionParser.
$options={}

class Screenplay 
    attr_reader :fdxFile
    attr_reader :baseName
    attr :title, true
    attr :author, true
    attr :cover, true

    # input: .fdx input file
    def initialize(fdxFile)
        @fdxFile=fdxFile
        @baseName=File.basename(fdxFile,".fdx")
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
    
    def blockquote(file,clazz, text)
        file.puts "<blockquote class=\"#{clazz}\">#{text}</blockquote>"
    end
    
    def blockquote2(file,clazz, text)
        file.puts "<blockquote><blockquote class=\"#{clazz}\">#{text}</blockquote></blockquote>"
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

    # create parent firectory of a file 
    def createDirectoryForFile(fileName)
        dirName=File.dirname(fileName)
        if (! File.directory?(dirName))    
            FileUtils.mkdir_p(dirName)
        end
    end
end

#
# .mobi generator
#
class MobiGenerator < BaseGenerator
    def generate(screenplay)
        @screenplay=screenplay
        parser=FdxParser.new(@screenplay.fdxFile)
        
        outputdir="__mobi"
        cleanDirectory(outputdir)
        Dir.mkdir(outputdir)
        FileUtils.cp(@screenplay.cover,outputdir)

        Dir.chdir(outputdir) do
            prepare_css("main.css")
            prepare_opf("ebook.opf")
            prepare_ncx("root.ncx")
            
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
            
            # we run kindlegen to generate the .mobi file
            cmdeLine = "kindlegen ebook.opf"     
             
            if ($options[:verbose])
                puts "Running command: #{cmdeLine}"
            end
            IO.popen(cmdeLine) { |io|
                io.each do |line|
                    if ($options[:verbose])
                        puts line
                    end
                end                
            }
            status = $?
            if ($options[:verbose])
                puts "Status code is #{status}"
            end
            # test the result of the build from $?
            # pierre:unfortunately the status code is not reliable
            #    to decide if the generation was correct or not
            #if (status != 0)
            #    puts "kindlegen failed"
            #end
            FileUtils.cp("ebook.mobi","../#{@screenplay.baseName}.mobi")
        end
        
        puts "Kindle file available:#{@screenplay.baseName}.mobi"
        
        if (! $options[:keep])
            cleanDirectory(outputdir)
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
####/
    end
    
    def fdx_dialogue(text)
        blockquote2(@bodyFile,"dialogue", text)
    end

    def fdx_parenthetical(text)
        blockquote2(@bodyFile,"parenthetical", text)
    end
    
    def a(file, name)
        file.puts "<a name=\"#{name}\"/>"
    end
    
    
    def prepare_css(fileName)
        createDirectoryForFile(fileName)
        File.open(fileName,'w') do |f|
            f.puts <<-'ENDTEXT'
.character {
  text-indent: 0em;
  text-align: center;
  margin-top: 10px;
}

.parenthetical {
  font-style: italic;
  font-size: 80%;
}

.dialogue {
}

.sceneheading {
  margin-top: 100px;
  text-indent: 0em;
  font-weight: bold;
}

.action {
  text-indent: 0em;
  margin-top: 10px;
}

.transition {
  text-align: right;
}

            ENDTEXT
        end 
    end
    
    def prepare_opf(fileName)
        createDirectoryForFile(fileName)

        t = Time.now
    
        File.open(fileName,'w') do |f|
            f.puts <<-HERE
<?xml version="1.0" encoding="UTF-8" ?>
<package version="2.0" unique-identifier="bookId" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>#{@screenplay.title}</dc:title>
    <dc:language>en</dc:language>
    <dc:identifier opf:scheme="URI" id="bookId">#{t.strftime("%Y/%m/%d")}-XX</dc:identifier>
    <dc:creator opf:role="aut">#{@screenplay.author}</dc:creator>
    <dc:publisher>@ebookineur</dc:publisher>
    <dc:date opf:event="publication">#{t.strftime("%Y-%m-%d")}</dc:date>
    <dc:description>Book generated by @ebookineur</dc:description>
    <meta name="cover" content="id-cover-image"/>
  </metadata>
  <manifest>
    <item id="id-cover-image" href="#{@screenplay.cover}" media-type="image/jpeg"/>
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
    
    
    def prepare_ncx(fileName)
        createDirectoryForFile(fileName)

        t = Time.now
    
        File.open(fileName,'w') do |f|
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
###### /
        end
    end
end

#
# .epub generator
#
class EpubGenerator < BaseGenerator
    def generate(screenplay)
        @screenplay=screenplay
        parser=FdxParser.new(@screenplay.fdxFile)
        
        outputdir="__epub"
        cleanDirectory(outputdir)
        Dir.mkdir(outputdir)
        FileUtils.mkdir_p("#{outputdir}/OPS/images")
        FileUtils.cp(@screenplay.cover,"#{outputdir}/OPS/images")
        Dir.chdir(outputdir) do
            prepare_containerXml("META-INF/container.xml")
            prepare_css("OPS/css/main.css")
            prepare_titlePage("OPS/title.xml")
            prepare_coverPage("OPS/cover.xml")
            prepare_opf("OPS/root.opf")
            prepare_ncx("OPS/root.ncx")
            @ncxFile = File.new("OPS/root.ncx", "a")
            prepare_content("OPS/content.xml")
            @bodyFile = File.new("OPS/content.xml", "a")
            parser.parse(self) 
            @ncxFile.puts <<-END
  </navMap>
</ncx>
END
            @ncxFile.close
            
            @bodyFile.puts <<-END
</div>
</body>
</html>
END
###/
            @bodyFile.close
            output_path="../#{@screenplay.baseName}.epub"
            if (File.exist?(output_path)) 
                FileUtils.rm(output_path)
            end
            
            # thank you to:
            # http://rubydoc.info/github/skoji/gepub/master/GEPUB/Generator#create_epub-instance_method
            Zip::ZipOutputStream::open(output_path) {
              |epub|
              epub.put_next_entry('mimetype', '', '', Zip::ZipEntry::STORED)
              epub << 'application/epub+zip'
        
              Dir["**/*"].each do
                |f|
                if File.basename(f) != 'mimetype' && !File.directory?(f)
                  File.open(f,'rb') do
                    |file|
                    epub.put_next_entry(f)
                    epub << file.read
                  end
                end
              end
            }
        end
        
        puts "Epub file available:#{@screenplay.baseName}.epub"
        
        if (! $options[:keep])
            cleanDirectory(outputdir)
        end
    end

    def fdx_scene_heading(text,sceneId,sceneCounter)
        a(@bodyFile,sceneId)
        p(@bodyFile,"sceneheading", text)
        
        @ncxFile.puts <<-END
    <navPoint id="#{sceneId}" playOrder="#{sceneCounter}">
      <navLabel>
        <text>#{text}</text>
      </navLabel>
      <content src="content.xml##{sceneId}"/>
    </navPoint>
END
####/
    end    
    
    def a(file, name)
        file.puts "<a id=\"#{name}\"/>"
    end
    
    
    def prepare_containerXml(fileName)
        createDirectoryForFile(fileName)
        File.open(fileName,'w') do |f|
            f.puts <<-'ENDTEXT'
<?xml version="1.0" encoding="UTF-8" ?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OPS/root.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
            ENDTEXT
        end
    end
    
    def prepare_css(fileName)
        createDirectoryForFile(fileName)
        File.open(fileName,'w') do |f|
            f.puts <<-'ENDTEXT'
            
p {
    line-height:120%;
    margin: 0px;
    padding: 0px;
}
            
.coverTitle {
    margin: 10px;
    padding: 10px;
    height: 150px;
    font-size:250%;
    text-align: center;
}

.coverSubtitle {
    margin: 0px;
    padding: 0px;
    height: 150px;
    font-size:200%;
    text-align: center;
}

.coverAuthor {
    margin: 10px;
    padding: 10px;
    height: 150px;
    text-align: right;
}

.character {
  text-indent: 0em;
  text-align: center;
  margin-top: 10px;
}

.parenthetical {
  margin-left: 50px; 
  text-indent: 0em;
  font-style: italic;
  font-size: 80%;
}

.dialogue {
  margin-left: 50px; 
  text-indent: 0em;
}

.sceneheading {
  margin-top: 100px;
  text-indent: 0em;
  font-weight: bold;
}

.action {
  text-indent: 0em;
  margin-top: 10px;
}

.transition {
  text-align: right;
}

            ENDTEXT
        end 
    end    
    
    def prepare_titlePage(fileName)
        createDirectoryForFile(fileName)
        File.open(fileName,'w') do |f|
            f.puts <<-ENDTEXT
<?xml version="1.0" encoding="UTF-8" ?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
  <link rel="stylesheet" href="css/main.css" type="text/css" />
  <title>Title Page</title>
  <meta http-equiv="Content-Type" content="application/xhtml+xml; charset=utf-8" />
</head>
<body>
<div class="document">
<p class="coverTitle">#{@screenplay.title}</p>
<p class="coverAuthor">#{@screenplay.author}</p>
</div>
</body>
</html>
            ENDTEXT
###"            
        end
    end
    
    def prepare_coverPage(fileName)
        createDirectoryForFile(fileName)
        File.open(fileName,'w') do |f|
            f.puts <<-ENDTEXT
<?xml version="1.0" encoding="UTF-8" ?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
  <link rel="stylesheet" href="css/main.css" type="text/css" />
  <title>Cover</title>
  <meta http-equiv="Content-Type" content="application/xhtml+xml; charset=utf-8" />
</head>
<body style="margin: 0; padding: 0; text-align: center;">
<div class="document">
<div style="text-align: center; page-break-after: always;">
 <img src="images/#{@screenplay.cover}" alt="cover" style="height: 100%; max-width: 100%;"/>
</div>
</div>
</body>
</html>
            ENDTEXT
###"            
        end
    end
    
    
    def prepare_opf(fileName)
        createDirectoryForFile(fileName)
        t = Time.now
        File.open(fileName,'w') do |f|
            f.puts <<-ENDTEXT
<?xml version="1.0" encoding="UTF-8" ?>
<package version="2.0" unique-identifier="bookId" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>#{@screenplay.title}</dc:title>
    <dc:language>en</dc:language>
    <dc:identifier opf:scheme="URI" id="bookId">#{t.strftime("%Y/%m/%d")}-XX</dc:identifier>
    <dc:creator opf:role="aut">#{@screenplay.author}</dc:creator>
    <dc:publisher>@ebookineur</dc:publisher>
    <dc:date opf:event="publication">#{t.strftime("%Y-%m-%d")}</dc:date>
    <dc:description>Book generated by @ebookineur</dc:description>
  </metadata>
  <manifest>
    <item id="cover" href="cover.xml" media-type="application/xhtml+xml"/>
    <item id="cover-image" href="images/#{@screenplay.cover}" media-type="image/jpeg"/>
    <item id="titlepage" href="title.xml" media-type="application/xhtml+xml"/>
    <item id="css-main" href="css/main.css" media-type="text/css"/>
    <item id="content" href="content.xml" media-type="application/xhtml+xml"/>
    <item id="ncx" href="root.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="cover"/>
    <itemref idref="titlepage"/>
    <itemref idref="content"/>
  </spine>
  <guide>
    <reference type="cover" title="Cover" href="cover.xml"/>
    <reference type="title-page" title="Title Page" href="title.xml"/>
    <reference type="text" title="#{@screenplay.title}" href="content.xml"/>
  </guide>
</package>

            ENDTEXT
###"            
        end
    end
    
    def prepare_ncx(fileName)
        createDirectoryForFile(fileName)
        t = Time.now
        File.open(fileName,'w') do |f|
            f.puts <<-ENDTEXT
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
    <navPoint class="titlepage" id="id-000" playOrder="0">
      <navLabel>
        <text>Title Page</text>
      </navLabel>
      <content src="title.xml"/>
    </navPoint>
            ENDTEXT
###/            
        end
    end
    
    
    def prepare_content(fileName)
        createDirectoryForFile(fileName)
        File.open(fileName,'w') do |f|
            f.puts <<-ENDTEXT
<?xml version="1.0" encoding="UTF-8" ?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
<head>
  <link rel="stylesheet" href="css/main.css" type="text/css" />
  <title>@{screenplay.title}</title>
  <meta http-equiv="Content-Type" content="application/xhtml+xml; charset=utf-8" />
</head>
<body>
<div class="document">

            ENDTEXT
###/"            
        end
    end
    
    
end

optparse = OptionParser.new do|opts|
   # Set a banner, displayed at the top
   # of the help screen.
   opts.banner = "Usage: fdx2ebook.rb [options] <file.fdx>]"
 
   # Define the options, and what they do
   $options[:verbose] = false
   opts.on( '-v', '--verbose', 'Output more information' ) do
     $options[:verbose] = true
   end
 
   $options[:title] = ""
   opts.on( '-t', '--title title', 'the title of the script' ) do |title|
     $options[:title] = title
   end
 
   $options[:author] = ""
   opts.on( '-a', '--author author', 'the author of the script' ) do |author|
     $options[:author] = author
   end
 
   $options[:cover] = ""
   opts.on( '-c', '--cover file.jpg', 'cover file' ) do |cover|
     $options[:cover] = cover
   end
 
   $options[:keep] = false
   opts.on( '-k', '--keep', 'Keep the generated file' ) do
     $options[:keep] = true
   end
 
   $options[:nomobi] = false
   opts.on( '-1', '--nomobi', 'skip the .mobi file generation' ) do
     $options[:nomobi] = true
   end
 
   $options[:noepub] = false
   opts.on( '-2', '--noepub', 'skip the .epub file generation' ) do
     $options[:noepub] = true
   end
 
   # This displays the help screen, all programs are
   # assumed to have this option.
   opts.on( '-h', '--help', 'Display this screen' ) do
     puts opts
     exit
   end
end
 
# Parse the command-line. Remember there are two forms
# of the parse method. The 'parse' method simply parses
# ARGV, while the 'parse!' method parses ARGV and removes
# any options found there, as well as any parameters for
# the options. What's left is the list of files to resize.
optparse.parse!

# Check the remaining of the command line
if (ARGV.size > 0) 
    fdxFileName = ARGV[0]
else
    puts "missing fdx file name"
    exit
end

if (File.extname(fdxFileName) != ".fdx")
    puts "Only .fdx extension are supported"
    exit
end

if (! File.exist?(fdxFileName)) 
    puts "the fdx file (#{fdxFileName}) does not exist"
    exit
end

if ($options[:title].length == 0)
    puts "missing title parameter"
    exit
end

if ($options[:author].length == 0)
    puts "missing author parameter"
    exit
end

if ($options[:cover].length == 0)
    puts "missing cover parameter"
    exit
end

if (! File.exist?($options[:cover])) 
    puts "the cover file (#{$options[:cover]}) does not exist"
    exit
end

if (File.extname($options[:cover]) != ".jpg" && File.extname($options[:cover]) != ".jpeg")
    puts "Only jpeg files are supported for cover images"
    exit
end



screenplay=Screenplay.new(fdxFileName)
screenplay.title=$options[:title]
screenplay.author=$options[:author]
screenplay.cover=$options[:cover]

if (! $options[:nomobi])
    generator=MobiGenerator.new
    generator.generate(screenplay)
end


if (! $options[:noepub])
    generator=EpubGenerator.new
    generator.generate(screenplay)
end
