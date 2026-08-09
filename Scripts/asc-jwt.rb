#!/usr/bin/ruby
#
# Mint a short-lived App Store Connect API token and print it.
#
# The API wants an ES256 JWT signed with the .p8 downloaded from App
# Store Connect > Integrations > Keys. This machine has no PyJWT and no
# gems worth depending on, so the token is assembled by hand against the
# OpenSSL that ships with the system ruby -- which is enough, because a
# JWT is two JSON blobs and a signature.
#
# The one part that is not obvious: OpenSSL signs ECDSA into DER, and
# JOSE wants the raw r||s pair, each left-padded to the 32 bytes of a
# P-256 coordinate. Handing the DER over unconverted gets a 401 that
# says nothing about why.
#
# Apple caps the lifetime at 20 minutes; ten is plenty for one script
# and leaves room for a slow clock.
#
# Credentials, the same three as Scripts/release-testflight.sh:
#
#   ASC_KEY_ID      the key's ID
#   ASC_ISSUER_ID   the issuer UUID shown above the key list
#   the .p8 itself in ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8
#
# Usage: normally through Scripts/asc-api.sh, or directly as
#
#   TOKEN="$(Scripts/asc-jwt.rb)"
#
require 'openssl'
require 'base64'
require 'json'

def fail_with(message)
  warn "asc-jwt: #{message}"
  exit 1
end

key_id = ENV['ASC_KEY_ID'].to_s
issuer = ENV['ASC_ISSUER_ID'].to_s
fail_with 'set ASC_KEY_ID' if key_id.empty?
fail_with 'set ASC_ISSUER_ID' if issuer.empty?

key_path = ENV['ASC_KEY_PATH'].to_s
key_path = File.join(Dir.home, '.appstoreconnect', 'private_keys', "AuthKey_#{key_id}.p8") if key_path.empty?
unless File.file?(key_path)
  fail_with "no key at #{key_path}\n" \
            '  Create one in App Store Connect > Integrations > Keys, download the ' \
            '.p8 once (Apple does not offer it twice), and put it there.'
end

def b64(data)
  Base64.urlsafe_encode64(data).delete('=')
end

now = Time.now.to_i
header = { alg: 'ES256', kid: key_id, typ: 'JWT' }
claims = { iss: issuer, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }
signing_input = "#{b64(JSON.dump(header))}.#{b64(JSON.dump(claims))}"

begin
  key = OpenSSL::PKey::EC.new(File.read(key_path))
rescue OpenSSL::PKey::ECError => e
  fail_with "#{key_path} is not a usable EC private key: #{e.message}"
end

der = key.sign(OpenSSL::Digest::SHA256.new, signing_input)
r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }

print "#{signing_input}.#{b64(r + s)}"
