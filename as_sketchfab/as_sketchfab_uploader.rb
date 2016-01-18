# ========================
# Main file for Sketchfab Uploader
# ========================


require 'sketchup'


# ========================
    

module AS_Extensions

  module AS_SketchfabUploader


      # ========================


      # Some general variables
      
      # Extension name for defaults etc.
      @extname = "as_Sketchfab"
      @extdir = File.dirname(__FILE__).tr("\\","/")

      # Set temporary folder locations and filenames
      # Don't use root or plugin folders because of writing permissions
      
      # Get temp directory for temporary file storage
      @user_dir = (defined? Sketchup.temp_dir) ? Sketchup.temp_dir : ENV['TMPDIR'] || ENV['TMP'] || ENV['TEMP']
      Sketchup.write_default @extname, "user_dir", @user_dir
      
      # Cleanup slashes
      @user_dir = @user_dir.tr("\\","/")
      @filename = File.join(@user_dir , 'temp_export.dae')
      @asset_dir = File.join(@user_dir, 'temp_export')
      @zip_name = File.join(@user_dir,'temp_export.zip')

      # Exporter options - doesn't work with KMZ export, though
      # Need to have instancing false as per Sketchfab
      @options_hash = { :triangulated_faces   => true,
                        :doublesided_faces    => false,
                        :edges                => true,
                        :materials_by_layer   => false,
                        :author_attribution   => true,
                        :texture_maps         => true,
                        :selectionset_only    => false,
                        :preserve_instancing  => false }

      # Add the library path so Ruby can find it
      $: << File.dirname(__FILE__)+'/lib'

      # Load libraries for 2013 and 2014
      require 'zip'


      # ========================


      def self.show_dialog_2013
      # This uses a json approach to upload (for < SU 2014)

          # Need to load the old Fileutils here
          require 'fileutils-186'

          # Allow for only selection upload if something is selected - reset var first
          @options_hash[:selectionset_only] = false
          if (Sketchup.active_model.selection.length > 0) then
              res = UI.messagebox "Upload only selected geometry?", MB_YESNO
              @options_hash[:selectionset_only] = true if (res == 6)
          end

          # Export model as DAE
          if Sketchup.active_model.export @filename, @options_hash then

              # Create ZIP file
              Zip.create(@zip_name, @filename, @asset_dir)

              # Open file as binary and encode it as Base64
              contents = open(@zip_name, "rb") {|io| io.read }
              encdata = [contents].pack('m')

              # Set up and show Webdialog
              dlg = UI::WebDialog.new('Sketchfab Uploader', false,'SketchfabUploader', 450, 520, 150, 150, true)
              dlg.navigation_buttons_enabled = false
              dlg.min_width = 450
              dlg.max_width = 450
              dlg.set_size(450,650)

              # Close dialog callback
              dlg.add_action_callback('close_me') {|d, p|
                  d.close
              }

              # Callback to prefill page elements (token)
              dlg.add_action_callback('prefill') {|d, p|
                  # Need to do this because we need to wait until page has loaded
                  mytoken = Sketchup.read_default @extname, "api_token", "Paste your token here"
                  c = "$('#token').val('" + mytoken + "')"
                  d.execute_script(c)
              }

              # Callback to send model
              dlg.add_action_callback('send') {|d, p|

                  # Get data from webdialog and clean it up a bit
                  description = d.get_element_value("description").gsub(/"/, "'")
                  mytitle = d.get_element_value("mytitle").gsub(/"/, "'")
                  tags = d.get_element_value("tags").gsub(/"/, "'")
                  tags.gsub!(/,*\s+/,' ')
                  private = d.get_element_value("private").gsub(/"/, "'")
                  password = d.get_element_value("password").gsub(/"/, "'")
                  privString = ''
                  if private == 'True' then
                      privString = ',"private":"true","password":"' + password + '"'
                  end

                  # Assemble JSON string
                  json = '{"contents":"' + encdata.split(/[\r\n]+/).join('\r\n') + '","filename":"model.zip","title":"' + mytitle + '","description":"' + description + '","tags":"' + tags + '","token":"' + p + '","source":"sketchup-exporter"' + privString + '}'

                  # Submit data to Sketchfab - need to use old API with JSON
                  d.post_url("https://api.sketchfab.com/model", json)

                  begin

                      # Then delete the temporary files
                      # File.delete @zip_name if File.exists?(@zip_name)
                      # File.delete @filename if File.exists?(@filename)
                      AS_SketchfabUploader::FileUtils.rm_f(@zip_name) if File.exists?(@zip_name)
                      AS_SketchfabUploader::FileUtils.rm_f(@filename) if File.exists?(@filename)
                      AS_SketchfabUploader::FileUtils.rm_r(@asset_dir) if File.exists?(@asset_dir)

                  rescue Exception => e

                      UI.messagebox e

                  end

                  Sketchup.write_default @extname, "api_token", p
                  d.execute_script('submitted()')

              }
              
              # Set dialog HTML from external file
              dlg.set_file(File.join(@extdir,'as_sketchfab_form2013.html'))
              dlg.show_modal

          else

              UI.messagebox "Couldn't export model as " + @filename

          end # if image converts

      end # show_dialog_2013


      # ========================


      def self.show_dialog_2014
      # This uses the Ruby NET StdLibs instead of json

          # Load Net and multipart post libraries for 2014
          require 'uri'
          require 'net/http'
          require 'net/https'
          require 'openssl'
          require 'multipart-post-as'
          require 'json'
          # Can load the new Fileutils here
          require 'fileutils'

          # Allow for only selection upload if something is selected - reset var first
          @options_hash[:selectionset_only] = false
          if (Sketchup.active_model.selection.length > 0) then
              res = UI.messagebox "Upload only selected geometry?", MB_YESNO
              @options_hash[:selectionset_only] = true if (res == 6)
          end

          # Set up and show Webdialog
          dlg = UI::WebDialog.new('Sketchfab Uploader', false,'SketchfabUploader', 450, 520, 150, 150, true)
          dlg.navigation_buttons_enabled = false
          dlg.min_width = 450
          dlg.max_width = 450
          dlg.set_size(450,650)

          # Close dialog callback
          dlg.add_action_callback('close_me') {|d, p|

              d.close

          }


          # Callback to prefill page elements (token)
          dlg.add_action_callback('prefill') {|d, p|

              # Prefill all form elements from registry here
              # Need to do this because we need to wait until page has loaded
              mytoken = Sketchup.read_default @extname, "api_token"
              edg = Sketchup.read_default @extname, "edges", "true"
              mat = Sketchup.read_default @extname, "materials", "false"  
              tex = Sketchup.read_default @extname, "textures", "true"
              fac = Sketchup.read_default @extname, "faces", "false"
              c = "$('#token').val('#{mytoken}');"
              d.execute_script(c)              
              c = "$('#edges').prop('checked',#{edg}); $('#materials').prop('checked',#{mat}); $('#textures').prop('checked',#{tex}); $('#faces').prop('checked',#{fac});"
              d.execute_script(c)            

          }


          # Callback to prepare and send model
          dlg.add_action_callback('send') {|d, p|

              # Get data from webdialog and clean it up a bit
              # Token is p
              description = d.get_element_value("description").gsub(/"/, "'")
              mytitle = d.get_element_value("mytitle").gsub(/"/, "'")
              tags = d.get_element_value("tags").gsub(/"/, "'")
              tags.gsub!(/,*\s+/,' ')
              private = d.get_element_value("private").gsub(/"/, "'")
              password = d.get_element_value("password").gsub(/"/, "'")
              edg = d.get_element_value("edges").gsub(/"/, "'")
              mat = d.get_element_value("materials").gsub(/"/, "'")
              tex = d.get_element_value("textures").gsub(/"/, "'")
              fac = d.get_element_value("faces").gsub(/"/, "'")
              # ins = d.get_element_value("instances").gsub(/"/, "'")
              
              # Write form elements to registry here
              Sketchup.write_default @extname, "api_token", p
              Sketchup.write_default @extname, "edges", edg
              Sketchup.write_default @extname, "materials", mat              
              Sketchup.write_default @extname, "textures", tex
              Sketchup.write_default @extname, "faces", fac
              # Sketchup.write_default @extname, "instances", ins
              
              # Adjust options from dialog
              (edg == "true") ? @options_hash[:edges] = true : @options_hash[:edges] = false
              (mat == "true") ? @options_hash[:materials_by_layer] = true : @options_hash[:materials_by_layer] = false
              (tex == "true") ? @options_hash[:texture_maps] = true : @options_hash[:texture_maps] = false
              (fac == "true") ? @options_hash[:doublesided_faces] = true : @options_hash[:doublesided_faces] = false
              # (ins == "true") ? @options_hash[:preserve_instancing] = true : @options_hash[:preserve_instancing] = false

              # Export model as DAE and process
              if Sketchup.active_model.export @filename, @options_hash then

                  # Some feedback while we wait
                  d.execute_script('submitted()')

                  # Wrap in rescue for error display
                  begin

                      # Create ZIP file
                      Zip.create(@zip_name, @filename, @asset_dir)
                      upfile = AS_SketchfabUploader::UploadIO.new(@zip_name, "application/zip")

                      # Compile data
                      data = {
                                'token' => p,
                                'fileModel' => upfile,
                                'title' => mytitle,
                                'description' => description,
                                'tags' => tags,
                                'private' => private,
                                'password' => password,
                                'source' => 'sketchup-exporter'
                      }

                      # Submission URL
                      url = 'https://api.sketchfab.com/v1/models'
                      uri = URI.parse(url)

                      # Prepare data for submission
                      req = AS_SketchfabUploader::Multipart.new uri.path, data

                      # Submit via SSL
                      https = Net::HTTP.new(uri.host, uri.port)
                      https.use_ssl = true
                      # Can't properly verify certificate with Sketchfab - OK here
                      https.verify_mode = OpenSSL::SSL::VERIFY_NONE
                      res = https.start { |cnt| cnt.request(req) }

                      # Now extract the resulting data
                      json = JSON.parse(res.body.gsub(/"/,"\""))
                      @success = json['success']

                      # Free some resources
                      upfile.close
                      GC.start

                  rescue Exception => e

                      UI.messagebox e

                  end

                  d.close

                  if @success then

                      # Get model info from result
                      @model_id = json['result']['id']

                      # Give option to open uploaded model
                      result = UI.messagebox 'Open Sketchfab model in your browser?', MB_YESNO
                      UI.openURL "https://sketchfab.com/show/#{@model_id}" if result == 6

                  else

                      fb = ""
                      fb = " Error: " + json['error'] if json
                      UI.messagebox "Sketchfab upload failed." + fb

                  end

                  begin

                      # Then delete the temporary files
                      # File.delete @zip_name if File.exists?(@zip_name)
                      # File.delete @filename if File.exists?(@filename)
                      FileUtils.rm_f(@zip_name) if File.exists?(@zip_name)
                      FileUtils.rm_f(@filename) if File.exists?(@filename)
                      FileUtils.rm_r(@asset_dir) if File.exists?(@asset_dir)

                  rescue Exception => e

                      UI.messagebox e

                  end

              else

                  d.close
                  UI.messagebox "Couldn't export model as " + @filename

              end

          }


          # Set dialog HTML from external file
          dlg.set_file(File.join(@extdir,'as_sketchfab_form2014.html'))
          dlg.show_modal


      end # show_dialog_2014


      # ========================


      # Create menu items
      unless file_loaded?(__FILE__)

        # Pick based on version
        if Sketchup.version.to_f < 14 then
          UI.menu("File").add_item("Upload to Sketchfab") {AS_SketchfabUploader::show_dialog_2013}
        else
          UI.menu("File").add_item("Upload to Sketchfab") {AS_SketchfabUploader::show_dialog_2014}
        end

        file_loaded(__FILE__)

      end


  end # module AS_SketchfabUploader

end # module AS_Extensions


# ========================
