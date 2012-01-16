# coding: UTF-8

require 'rubygems/test_case'

class TestGemSecurityPolicy < Gem::TestCase

  ALTERNATE_KEY    = load_key 'alternate'
  INVALID_KEY      = load_key 'invalid'
  CHILD_KEY        = load_key 'child'
  GRANDCHILD_KEY   = load_key 'grandchild'
  INVALIDCHILD_KEY = load_key 'invalidchild'

  ALTERNATE_CERT      = load_cert 'alternate'
  CHILD_CERT          = load_cert 'child'
  EXPIRED_CERT        = load_cert 'expired'
  FUTURE_CERT         = load_cert 'future'
  GRANDCHILD_CERT     = load_cert 'grandchild'
  INVALIDCHILD_CERT   = load_cert 'invalidchild'
  INVALID_ISSUER_CERT = load_cert 'invalid_issuer'
  INVALID_SIGNER_CERT = load_cert 'invalid_signer'
  WRONG_KEY_CERT      = load_cert 'wrong_key'

  def setup
    super

    @spec = quick_gem 'a' do |s|
      s.description = 'π'
      s.files = %w[lib/code.rb]
    end

    @sha1 = OpenSSL::Digest::SHA1
    @trust_dir = Gem::Security::OPT[:trust_dir]

    @almost_no = Gem::Security::AlmostNoSecurity
    @low       = Gem::Security::LowSecurity
    @high      = Gem::Security::HighSecurity

    @chain = Gem::Security::Policy.new(
      'Chain',
      :verify_data   => true,
      :verify_signer => true,
      :verify_chain  => true,
      :verify_root   => false,
      :only_trusetd  => false,
      :only_signed   => false
    )

    @root = Gem::Security::Policy.new(
      'Root',
      :verify_data   => true,
      :verify_signer => true,
      :verify_chain  => true,
      :verify_root   => true,
      :only_trusetd  => false,
      :only_signed   => false
    )
  end

  def test_check_data
    data = @sha1.digest 'hello'

    signature = sign data

    assert @almost_no.check_data(PUBLIC_KEY, @sha1, signature, data)
  end

  def test_check_data_invalid
    data = @sha1.digest 'hello'

    signature = sign data

    invalid = @sha1.digest 'hello!'

    e = assert_raises Gem::Security::Exception do
      @almost_no.check_data PUBLIC_KEY, @sha1, signature, invalid
    end

    assert_equal 'invalid signature', e.message
  end

  def test_check_chain
    chain = [PUBLIC_CERT, CHILD_CERT, GRANDCHILD_CERT]

    assert @chain.check_chain chain, Time.now
  end

  def test_check_chain_invalid
    chain = [PUBLIC_CERT, CHILD_CERT, INVALIDCHILD_CERT]

    e = assert_raises Gem::Security::Exception do
      @chain.check_chain chain, Time.now
    end

    assert_equal "invalid signing chain: " \
                 "certificate #{INVALIDCHILD_CERT.subject} " \
                 "was not issued by #{CHILD_CERT.subject}", e.message
  end

  def test_check_cert
    assert @low.check_cert(PUBLIC_CERT, nil, Time.now)
  end

  def test_check_cert_expired
    e = assert_raises Gem::Security::Exception do
      @low.check_cert EXPIRED_CERT, nil, Time.now
    end

    assert_equal "certificate #{EXPIRED_CERT.subject} " \
                 "not valid after #{EXPIRED_CERT.not_after}",
                 e.message
  end

  def test_check_cert_future
    e = assert_raises Gem::Security::Exception do
      @low.check_cert FUTURE_CERT, nil, Time.now
    end

    assert_equal "certificate #{FUTURE_CERT.subject} " \
                 "not valid before #{FUTURE_CERT.not_before}",
                 e.message
  end

  def test_check_cert_invalid_issuer
    e = assert_raises Gem::Security::Exception do
      @low.check_cert INVALID_ISSUER_CERT, PUBLIC_CERT, Time.now
    end

    assert_equal "certificate #{INVALID_ISSUER_CERT.subject} " \
                 "was not issued by #{PUBLIC_CERT.subject}",
                 e.message
  end

  def test_check_cert_issuer
    assert @low.check_cert(CHILD_CERT, PUBLIC_CERT, Time.now)
  end

  def test_check_root
    chain = [PUBLIC_CERT, CHILD_CERT, INVALIDCHILD_CERT]

    assert @chain.check_root chain, Time.now
  end

  def test_check_root_invalid_signer
    chain = [INVALID_SIGNER_CERT]

    e = assert_raises Gem::Security::Exception do
      @chain.check_root chain, Time.now
    end

    assert_equal "certificate #{INVALID_SIGNER_CERT.subject} " \
                 "was not issued by #{INVALID_SIGNER_CERT.issuer}",
                 e.message
  end

  def test_check_root_not_self_signed
    chain = [INVALID_ISSUER_CERT]

    e = assert_raises Gem::Security::Exception do
      @chain.check_root chain, Time.now
    end

    assert_equal "root certificate #{INVALID_ISSUER_CERT.subject} " \
                 "is not self-signed (issuer #{INVALID_ISSUER_CERT.issuer})",
                 e.message
  end

  def test_check_trust
    Gem::Security.add_trusted_cert PUBLIC_CERT

    assert @high.check_trust [PUBLIC_CERT], @sha1, @trust_dir
  end

  def test_check_trust_child
    Gem::Security.add_trusted_cert PUBLIC_CERT

    assert @high.check_trust [PUBLIC_CERT, CHILD_CERT], @sha1, @trust_dir
  end

  def test_check_trust_mismatch
    Gem::Security.add_trusted_cert PUBLIC_CERT

    e = assert_raises Gem::Security::Exception do
      @high.check_trust [WRONG_KEY_CERT], @sha1, @trust_dir
    end

    assert_equal "trusted root certificate #{PUBLIC_CERT.subject} checksum " \
                 "does not match signing root certificate checksum", e.message
  end

  def test_check_trust_no_trust
    e = assert_raises Gem::Security::Exception do
      @high.check_trust [PUBLIC_CERT], @sha1, @trust_dir
    end

    assert_equal "root cert #{PUBLIC_CERT.subject} is not trusted", e.message
  end

  def test_check_trust_no_trust_child
    e = assert_raises Gem::Security::Exception do
      @high.check_trust [PUBLIC_CERT, CHILD_CERT], @sha1, @trust_dir
    end

    assert_equal "root cert #{PUBLIC_CERT.subject} is not trusted " \
                 "(root of signing cert #{CHILD_CERT.subject})", e.message
  end

  def test_verify_signature_chain
    data = @sha1.digest 'hello'

    signature = sign data, CHILD_KEY

    assert @chain.verify_signature signature, data, [PUBLIC_CERT, CHILD_CERT]
  end

  def test_verify_signature_data
    data = @sha1.digest 'hello'

    signature = sign data

    @almost_no.verify_signature signature, data, [PUBLIC_CERT]
  end

  def test_verify_signature_root
    data = @sha1.digest 'hello'

    signature = sign data, CHILD_KEY

    assert @root.verify_signature signature, data, [PUBLIC_CERT, CHILD_CERT]
  end

  def test_verify_signature_signer
    data = @sha1.digest 'hello'

    signature = sign data

    assert @low.verify_signature signature, data, [PUBLIC_CERT]
  end

  def test_verify_signature_trust
    Gem::Security.add_trusted_cert PUBLIC_CERT

    data = @sha1.digest 'hello'

    signature = sign data, PRIVATE_KEY

    assert @high.verify_signature signature, data, [PUBLIC_CERT]
  end

  def test_verify_signatures
    Gem::Security.add_trusted_cert PUBLIC_CERT

    digest = Gem::Security::OPT[:dgst_algo]

    @spec.cert_chain = [PUBLIC_CERT.to_s]

    metadata_gz = Gem.gzip @spec.to_yaml

    package = Gem::Package.new 'nonexistent.gem'

    metadata_gz_digest = package.digest StringIO.new metadata_gz

    digests = {}
    digests['metadata.gz'] = metadata_gz_digest

    signatures = {}
    signatures['metadata.gz'] =
      PRIVATE_KEY.sign digest.new, metadata_gz_digest.digest

    Gem::Security::HighSecurity.verify_signatures @spec, digests, signatures
  end

  def test_verify_signatures_missing
    Gem::Security.add_trusted_cert PUBLIC_CERT

    digest = Gem::Security::OPT[:dgst_algo]

    @spec.cert_chain = [PUBLIC_CERT.to_s]

    metadata_gz = Gem.gzip @spec.to_yaml

    package = Gem::Package.new 'nonexistent.gem'

    metadata_gz_digest = package.digest StringIO.new metadata_gz

    digests = {}
    digests['metadata.gz'] = metadata_gz_digest
    digests['data.tar.gz'] = package.digest StringIO.new 'hello' # fake

    signatures = {}
    signatures['metadata.gz'] =
      PRIVATE_KEY.sign digest.new, metadata_gz_digest.digest

    e = assert_raises Gem::Security::Exception do
      Gem::Security::HighSecurity.verify_signatures @spec, digests, signatures
    end

    assert_equal 'missing signature for data.tar.gz', e.message
  end

  def sign data, key = PRIVATE_KEY
    key.sign @sha1.new, data
  end

end

