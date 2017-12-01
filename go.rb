require 'twitter'
require 'YAML'
require 'JSON'
require 'fileutils'
#require 'aws-sdk'
require 'date'
require 'digest/sha1'
require File.expand_path(File.dirname(__FILE__)) + '/mRandelbot'


COORDS_REGEX = /([-+]?\d\.\d+(?:[eE][+-]\d{2,3})),\s*([-+]?\d\.\d+(?:[eE][+-]\d{2,3}))/

=begin
JIT generation and publishing

# Read current runsheet
# If none found, start a new one
# Get last plot. If none, generate a seed
# If last plot was unpublished, publish, save run sheet, and quit
# Perform edge plot and and randomly zoom
# Update run sheet with new coordinates
# Save run sheet
# Publish
# Update run sheet as published
# Save run sheet
# Quit

=end
def seed_points_up_to m, seed_until
    r = -0.75
    i = 0
    z = 1

    while z < seed_until
        r, i = get_a_point m, r, i, z
        
        z *= rand() * 4 + 2
    end

    return r,i,z
end

def get_a_point m, real, imaginary, zoom
    result = `#{m.config["mandelbrot"]} -mode=edge -w=1000 -h=1000 -z=#{zoom} -r=#{real} -i=#{imaginary}`.chomp
    parsed_coords  = result.scan(COORDS_REGEX)[0]
    return parsed_coords[0], parsed_coords[1]
end

def add_meta_data filename, exiftool, real, imag, zoom
    
      `#{exiftool} -gps:GPSLongitude="#{real}" #{filename}`
      `#{exiftool} -gps:GPSLongitudeRef="W" #{filename}` if real.to_f < 0
    
      `#{exiftool} -gps:GPSLatitude="#{imag}" #{filename}`
      `#{exiftool} -gps:GPSLatitudeRef="S" file` if imag.to_f < 0
    
      `#{exiftool} -DigitalZoomRatio="#{zoom}" #{filename}`
      `#{exiftool} exiftool -delete_original! #{filename}`
end

m = Mrandelbot.new

a = m.get_album

base_path = File.join(m.base_path, a[:album])

Dir.mkdir(base_path) if !Dir.exists?(base_path)

plot = a[:points].sort{|a,b| a["zoom"] <=> b["zoom"]}.last
real, imaginary, zoom = nil
if !plot
    real, imaginary, zoom = seed_points_up_to m, 50
else
    p plot
    z = plot["zoom"]
    r = plot["coords"][0]
    i = plot["coords"][1]
    zoom = z * rand() * 4 + 2
    real, imaginary = get_a_point m, r, i, zoom
end

plot = {zoom: zoom, coords: [real, imaginary], published: false}
a[:points] << plot
m.save_album a

filename = `#{m.config["mandelbrot"]} -z=#{zoom} -r=#{real} -i=#{imaginary} -c=true -o=#{base_path} -g='#{a[:gradient]}'`.chomp
a[:points].last[:filename] = filename
m.save_album a

add_meta_data filename, m.config["exiftool_path"], real, imaginary, zoom

if m.config["mode"] != "DEV"
    client = Twitter::REST::Client.new do |twitter|
        twitter.consumer_key = m.config["twitter"]["CONSUMER_KEY"]
        twitter.consumer_secret = m.config["twitter"]["CONSUMER_SECRET"]
        twitter.access_token = m.config["twitter"]["OAUTH_TOKEN"]
        twitter.access_token_secret = m.config["twitter"]["OAUTH_TOKEN_SECRET"]
    end
 
    File.open(filename, "r") do |file|
        tweet = client.update_with_media("#{real} + #{imaginary}i at zoom #{zoom}", file, {:lat=>imaginary, :long=>real, :display_coordinates=>'true'})
        a[:points].last[:tweet] = tweet.id
        m.save_album a
    end
end

a[:points].last[:published] = true
m.save_album a


