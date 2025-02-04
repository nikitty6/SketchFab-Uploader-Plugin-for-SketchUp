# ========================
# Main file for Sketchfab Uploader
# ========================


require 'sketchup'


# ========================
    

module AS_Extensions

  module AS_SketchfabUploader


      # ========================


      # Some general variables

      # Set temporary folder locations and filenames
      # Don't use root or plugin folders because of writing permissions
      # Get temp directory for temporary file storage
      @user_dir = (defined? Sketchup.temp_dir) ? Sketchup.temp_dir : ENV['TMPDIR'] || ENV['TMP'] || ENV['TEMP']
      # Cleanup slashes
      @user_dir = @user_dir.tr("\\","/")
      @filename = File.join(@user_dir , 'temp_export.dae')
      @asset_dir = File.join(@user_dir, 'temp_export')
      @zip_name = File.join(@user_dir,'temp_export.zip')

      # Exporter options - doesn't work with KMZ export, though
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
              logo = File.join(File.dirname(__FILE__) , 'uploader-logo.png')

              # Close dialog callback
              dlg.add_action_callback('close_me') {|d, p|
                  d.close
              }

              # Callback to prefill page elements (token)
              dlg.add_action_callback('prefill') {|d, p|
                  # Need to do this because we need to wait until page has loaded
                  mytoken = Sketchup.read_default "Sketchfab", "api_token", "Paste your token here"
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

                  defaults = Sketchup.write_default "Sketchfab", "api_token", p
                  d.execute_script('submitted()')

              }

              dlg_html = %Q~
              <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
              <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Sketchfab.com Uploader</title>
              <style type="text/css">
                  * {font-family: Arial, Helvetica, sans-serif; font-size:13px;}
                  body {background-color:#3d3d3d;padding:10px;min-width:220px;}
                  h1, label, p {color:#eee; font-weight: bold;}
                  h1 {font-size:2em;color:orange}
                  a, a:hover, a:visited {color:orange}
                  input, button, textarea {color:#fff; background-color:#666; border:none;}
                  label {display: block; width: 150px;float: left;}
              </style>
              <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.7.2/jquery.min.js"></script>
              </head>
              <body>
              <img src="#{logo}" style="width:100%;" />
              <p id="text">This dialog uploads the currently open model to Sketchfab.com. All fields marked with a * are mandatory.
              You can get your API token from the <a href='http://sketchfab.com' title='http://sketchfab.com' target='_blank'>Sketchfab website</a> after registering there.</p>
              <form id="SketchfabSubmit" name="SketchfabSubmit" action="">
                  <p><label for="mytitle">Model title *</label><input type="text" id="mytitle" name="mytitle" style="width:200px;" /></p>
                  <p><label for="description">Description</label><textarea name="description" id="description" style="height:3em;width:200px;"></textarea></p>
                  <p><label for="tags">Tags (space-separated)</label><input type="text" id="tags" name="tags" value="sketchup" style="width:200px;" /></p>
                  <p><label for="private">Make model private?</label><input type="checkbox" name="private" id="private" value="" /> <span style="font-weight:normal;">(PRO account required)</span></p>
                  <p id="pw-field" style="display:none;"><label for="password">Password</label><input type="text" name="password" id="password" value="" style="width:200px;" /></p>
                  <p><label for="token">Your API token *</label><input type="text" name="token" id="token" value="" style="width:200px;" /></p>
                  <p><input type="submit" id="submit" value="Submit Model" style="font-weight:bold;" /></p>
              </form>
              <p><span style="float:left;"><button value="Cancel" id="cancel">Dismiss</button></span><span style="float:right;margin-top:10px;">&copy; 2012-2014 by <a href="http://www.alexschreyer.net/" title="http://www.alexschreyer.net/" target="_blank" style="color:orange">Alex Schreyer</a></span></p>
              <p></p>
              <script type="text/javascript">
              $(function(){
                $("#SketchfabSubmit").submit(function(event){
                      event.preventDefault();

                      if ($('#mytitle').val().length == 0) {
                          alert('You must fill in a title.');
                          return false;
                      }

                      if ($('#token').val().length < 32) {
                          alert('Your token looks like it is too short. Please double-check.');
                          return false;
                      }

                      // Submit form and give feedback
                      token = $('#token').val();
                      window.location='skp:send@'+token;
                });
              });
              $('#cancel').click(function(){
                  window.location='skp:close_me';
              });

              $('#private').click(function(){
                  if ($(this).val() == 'True') {
                      $(this).val('');
                  } else {
                      $(this).val('True');
                  };
                  $('#pw-field').toggle();
              });

              $(document).ready(function() {
                  window.location='skp:prefill';
              });

              function submitted() {
                  $('h1').html('Model Submitted');
                  scomment = "Your model has been submitted. You can soon find it on your <a href='http://sketchfab.com/dashboard/' title='http://sketchfab.com/dashboard/' target='_blank'>Sketchfab dashboard</a>.<br /><br />"+
                  "Before closing this dialog, please wait until:<br /><br />"+
                  "<i>On Windows:</i> a browser download dialog opens (you can cancel it).<br /><br />"+
                  "<i>On the Mac:</i> this dialog changes into a confirmation code (close it afterwards).";
                  $('#text').html(scomment);
                  $('form').html('');
              };

              </script>
              </body></html>
              ~ # End of HTML

              dlg.set_html(dlg_html)
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
          logo = File.join(File.dirname(__FILE__) , 'uploader-logo.png')


          # Close dialog callback
          dlg.add_action_callback('close_me') {|d, p|

              d.close

          }


          # Callback to prefill page elements (token)
          dlg.add_action_callback('prefill') {|d, p|

              # Need to do this because we need to wait until page has loaded
              mytoken = Sketchup.read_default "as_Sketchfab", "api_token", "Paste your token here"
              c = "$('#token').val('" + mytoken + "')"
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

              # Adjust options from dialog
              (edg == "True") ? @options_hash[:edges] = true : @options_hash[:edges] = false
              (mat == "True") ? @options_hash[:materials_by_layer] = true : @options_hash[:materials_by_layer] = false
              (tex == "True") ? @options_hash[:texture_maps] = true : @options_hash[:texture_maps] = false
              (fac == "True") ? @options_hash[:doublesided_faces] = true : @options_hash[:doublesided_faces] = false

              # Export model as KMZ and process
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

                  # Save token for the next time
                  defaults = Sketchup.write_default "as_Sketchfab", "api_token", p

              else

                  d.close
                  UI.messagebox "Couldn't export model as " + @filename

              end

          }


          # Set dialog HTML
          dlg_html = %Q~
          <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
          <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Sketchfab.com Uploader</title>
          <style type="text/css">
              * {font-family: Arial, Helvetica, sans-serif; font-size:13px;}
              body {background-color:#3d3d3d;padding:10px;min-width:220px;}
              h1, label, p {color:#eee; font-weight: bold;}
              h1 {font-size:2em;color:orange}
              a, a:hover, a:visited {color:orange}
              input, button, textarea {color:#fff; background-color:#666; border:none;}
              label {display: block; width: 150px;float: left;}
          </style>
          <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.7.2/jquery.min.js"></script>
          </head>
          <body>
          <img src="#{logo}" style="width:100%;" />
          <p id="text">This dialog uploads the currently open model to Sketchfab.com. All fields marked with a * are mandatory.
          You can get your API token from the <a href='http://sketchfab.com' title='http://sketchfab.com' target='_blank'>Sketchfab website</a> after registering there.</p>
          <form id="SketchfabSubmit" name="SketchfabSubmit" action="">
              <p><label for="mytitle">Model title *</label><input type="text" id="mytitle" name="mytitle" style="width:200px;" /></p>
              <p><label for="description">Description</label><textarea name="description" id="description" style="height:3em;width:200px;"></textarea></p>
              <p><label for="tags">Tags (space-separated)</label><input type="text" id="tags" name="tags" value="sketchup" style="width:200px;" /></p>
              <p><label for="private">Make model private?</label><input type="checkbox" name="private" id="private" value="" /> <span style="font-weight:normal;">(PRO account required)</span></p>
              <p id="pw-field" style="display:none;"><label for="password">Password</label><input type="text" name="password" id="password" value="" style="width:200px;" /></p>
              <p><label for="token">Your API token *</label><input type="text" name="token" id="token" value="" style="width:200px;" /></p>
              <p><label for="options">Options:</label><input class="cbox" type="checkbox" name="edges" id="edges" checked="true" value="True" /> Export edges<br />
              <input class="cbox" type="checkbox" style="margin-left:150px;" name="textures" id="textures" checked="true" value="True" /> Export textures<br />
              <input class="cbox" type="checkbox" style="margin-left:150px;" name="faces" id="faces" value="" /> Export two-sided faces<br />
              <input class="cbox" type="checkbox" style="margin-left:150px;" name="materials" id="materials" value="" /> Use 'color by layer' materials
              </p>
              <p><input type="submit" id="submit" value="Submit Model" style="font-weight:bold;" /></p>
          </form>
          <p><span style="float:left;"><button value="Cancel" id="cancel">Dismiss</button></span><span style="float:right;margin-top:10px;">&copy; 2012-2014 by <a href="http://www.alexschreyer.net/" title="http://www.alexschreyer.net/" target="_blank" style="color:orange">Alex Schreyer</a></span></p>
          <p></p>
          <script type="text/javascript">
          $(function(){
            $("#SketchfabSubmit").submit(function(event){
                  event.preventDefault();

                  if ($('#mytitle').val().length == 0) {
                      alert('You must fill in a title.');
                      return false;
                  }

                  if ($('#token').val().length < 32) {
                      alert('Your token looks like it is too short. Please double-check.');
                      return false;
                  }

                  // Submit form and give feedback
                  token = $('#token').val();
                  window.location='skp:send@'+token;
            });
          });
          $('#cancel').click(function(){
              window.location='skp:close_me';
          });

          $('#private').click(function(){
              if ($(this).val() == 'True') {
                  $(this).val('');
              } else {
                  $(this).val('True');
              };
              $('#pw-field').toggle();
          });

          $('.cbox').click(function(){
              if ($(this).val() == 'True') {
                  $(this).val('');
              } else {
                  $(this).val('True');
              };
          });

          $(document).ready(function() {
              window.location='skp:prefill';
          });

          function submitted() {
              $('h1').html('Processing...');
              scomment = 'Your model has been submitted. Please hang on while we wait for a response from Sketchfab.';
              $('#text').html(scomment);
              $('form').html('');
          };

          </script>
          </body></html>
          ~ # End of HTML
          dlg.set_html(dlg_html)
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