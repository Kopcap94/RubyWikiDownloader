# encoding: UTF-8

require 'fileutils'
require 'open-uri'
require 'mediawiki_api'
require 'faraday'
#require 'openssl'
# In case if you have problems with SSL verification, uncomment first and last
# lines of this message. Use this SSL-solve method on your own risk!
#OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

module RubyDownloader
  PATH = File.dirname(__FILE__)

  CFG_PATH = PATH + '/config.json'
  I18N_PATH = PATH + '/i18n.json'
  ERR_PATH = PATH + '/errors.log'
  FILE_PATH = PATH + '/Files'

  class << self
    attr_accessor :cfg, :msg

    def init
      puts "Loading..."

      # Running file check system
      unless File.exists?( CFG_PATH )
        puts "Config file was not found. Creating new one in downloader folder."

        File.open( CFG_PATH, 'w+' ) {|f| f.write( JSON.pretty_generate({
          'nickname' => 'Your nickname here',
          'password' => 'Your password here',
          'script_lang' => 'en',
          'wikiname' => {
            'from' => 'community',
            'to' => 'ru.community',
            'page' => ''
          },
          'list' => 'filelist.txt',
          'comment' => 'Uploading image',
          'text' => '',
          'direct' => false
        }))}

        puts "Done! Fill it up and run again!"
        quit
      end

      # Load i18n file
      unless File.exists?( I18N_PATH )
        puts "Downloading i18n"

        open( I18N_PATH, 'wb' ) do | f |
          f << open( "https://raw.githubusercontent.com/Kopcap94/RubyWikiDownloader/master/i18n.json" ).read
        end
      end

      # Check folder
      unless File.directory?( FILE_PATH )
        FileUtils.mkdir_p( FILE_PATH )
      end

      load_cfg

      unless File.exists?( PATH + '/' + @cfg[ 'list' ] )
        puts @msg[ 'list-not-exist' ]
        quit
      end

      menu( false, '' )
    end

    def load_cfg
      # Load config and i18n file
      @cfg = JSON.parse( File.read( CFG_PATH ) )

      i18n = JSON.parse( File.read( I18N_PATH ) )
      lang = @cfg[ 'script_lang' ]

      @msg = i18n[ 'langs' ].include?( lang ) ? i18n[ lang ] : i18n[ 'en' ]
    end

    def menu( s, m )
      cls

      puts ( s ? "#{ m }\n\n" : "" ) + @msg[ 'menu' ] + 
            "\n[ 1 ] " + @msg[ 'menu-program' ] + 
            "\n[ 2 ] " + @msg[ 'menu-helper' ] + 
            "\n[ 3 ] " + @msg[ 'menu-reload' ] +
            "\n" + @msg[ 'menu-select' ]
 
      opt = gets.chomp.to_i
 
      case opt
      when 1
        _t = RubyDownloader::Main.new( self )
      when 2
        _t = RubyDownloader::Helper.new( self )
      when 3
        load_cfg
        menu( true, @msg[ 'menu-reload-done' ] )
      else
        menu( true, @msg[ 'menu-wrong-input' ] )
      end

      _t = _t.start
    end

    def cls
      Gem.win_platform? ? ( system "cls" ) : ( system "clear" )
    end

    def main
      puts @msg[ 'menu-return' ]
      gets
      menu( false, '' )
    end

    def quit
      puts "Press enter to exit"
      gets
      exit
    end
  end

  class Main
    def initialize( s )
      @cfg = s.cfg
      @msg = s.msg
      file = PATH + '/' + @cfg[ 'list' ]

      if File.zero?( file ) then
        puts @msg[ 'list-is-empty' ]

        RubyDownloader.quit
      end

      @filelist = File.read( file ).split( /\n/ )

      log_in
    end

    def log_in
      # Logging on wiki
      @c_from = MediawikiApi::Client.new( "http://#{ @cfg[ 'wikiname' ][ 'from' ] }.wikia.com/api.php" )

      # Checking if user seleted direct uploading
      if @cfg[ 'direct' ] then
        # Logging on target to upload wiki
        puts @msg[ 'log-in' ]

        begin
          @c_to = MediawikiApi::Client.new( "http://#{ @cfg[ 'wikiname' ][ 'to' ] }.wikia.com/api.php" )
          @c_to.log_in( @cfg['nickname'], @cfg['password'] )
        rescue => err
          msg = @msg[ 'log-in-error' ] % @cfg[ 'wikiname' ][ 'to' ]

          log_err( "#{ msg }\n #{ err.backtrace.join( "\n" ) }" )
          puts msg

          RubyDownloader.quit
        end

        # Token
        puts @msg[ 'token' ]
        @token = @c_to.prop( :info, titles: 'ItsARandomRubyDownloaderPage', intoken: 'edit' ).data[ 'pages' ][ '-1' ][ 'edittoken' ]
      end
    end

    def start
      # Progress variables
      all_f = @filelist.count()
      done_f = 0
      err_counter = 0

      # Reading file list
      @filelist.each do | line |
        begin
          done_f += 1
          progress = ( done_f.to_f / all_f.to_f ) * 100

          system( "echo \"\033]0;#{ @msg[ 'status-msg' ] % [ "#{ progress.floor }%", done_f, all_f, err_counter, line ] }\007\"" )
          RubyDownloader.cls

          @c_from.query( titles: "File:#{ line } ", prop: 'imageinfo', iiprop: 'url' ).data[ 'pages' ].each do | k, v |

            f_name = line.gsub( /["?]/, '-' ) #
            path = FILE_PATH + "/" + f_name
            url = v[ 'imageinfo' ][ 0 ][ 'url' ]

            open( path, 'wb' ) do | f |
              puts @msg[ 'dwn-file' ]
              f << open( url ).read
            end

            if @cfg[ 'direct' ] then
              puts @msg[ 'upload-file' ]

              io_f = Faraday::UploadIO.new( path, 'image/png' )
              @c_to.action( :upload, filename: f_name, file: io_f, comment: @cfg[ 'comment' ], ignorewarnings: 1, text: @cfg[ 'text' ], token_type: false, token: @token )
            end

            puts @msg[ 'done' ]
          end
        rescue => err
          err_counter += 1

          puts @msg[ 'dwn-error' ] % [ line, err.inspect ]
          log_err( "="*80 + "#{ line }:\n#{ err.backtrace.join( "\n" ) }\n" + "="*80 )

          next
        end
      end

      # On done
      RubyDownloader.cls
      puts @msg[ 'is-done' ]
      RubyDownloader.main
    end

    def log_err( m )
      File.open( ERR_PATH, 'a' ) { | f | f.write( "#{ m }\n" )}
    end
  end

  class Helper
    def initialize( s )
      @page = s.cfg[ 'wikiname' ][ 'page' ]

      if @page == "" then
        puts @msg[ 'helper-empty-value' ]
        RubyDownloader.main
      end

      @file = s.cfg[ 'list' ]
      @msg = s.msg
      @wiki = MediawikiApi::Client.new( "http://#{ s.cfg[ 'wikiname' ][ 'from' ] }.wikia.com/api.php" )
      @list = ""
    end

    def start
      RubyDownloader.cls

      puts @msg[ 'helper-intro' ] + "\n" + ( @msg[ 'helper-page' ] % @page )
      gets
      puts @msg[ 'helper-progress' ]

      res = @wiki.query( titles: @page, prop: 'images', imlimit: 5000, bot: 1 )
      d = res.data[ 'pages' ]

      if !d[ "-1" ].nil? then
        puts @msg[ 'helper-missing-page' ] % @page
        RubyDownloader.main
      end

      d.each do | k, v |
        v[ 'images' ].each { | obj | @list += "#{ obj[ 'title' ].gsub( /^[^:]+:/, '') }\n" }
      end

      if !res[ 'query-continue' ].nil? then
        r = true
        c = res[ 'query-continue' ][ 'images' ][ 'imcontinue' ]

        while r
          res = @wiki.query( titles: @page, prop: 'images', imlimit: 5000, imcontinue: c )

          d = res.data[ 'pages' ]
          d.each do | k, v |
            v[ 'images' ].each { | obj | @list += "#{ obj[ 'title' ].gsub( /^[^:]+:/, '') }\n" }
          end

          if res[ 'query-continue' ].nil? then
            r = false
          else
            c = res[ 'query-continue' ][ 'images' ][ 'imcontinue' ]
          end
        end
      end

      File.open( PATH + '/' + @file, 'w+' ) {|f| f.write( @list )}
      puts @msg[ 'helper-done' ] % @file

      RubyDownloader.main
    end
  end
end

RubyDownloader.init
