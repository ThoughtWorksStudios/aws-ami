Gem::Specification.new do |s|
  s.name = 'aws-ami'
  s.version = '0.0.9'
  s.summary = 'A tool for creating AWS AMI from a base AMI and an install packages script'
  s.license = 'MIT'
  s.authors = ["Mingle SaaS team"]
  s.email = 'mingle.saas@thoughtworks.com'
  s.homepage = 'http://github.com/ThoughtWorksStudios/aws-ami'


  s.add_dependency('aws-sdk', '~> 1.8.2')

  s.files = ['README']
  s.files += Dir['lib/**/*.rb']
  s.files += Dir['bin/*']
  s.files += Dir['lib/**/*.json']

  s.bindir = 'bin'
  s.executables = 'aws-ami'

  s.post_install_message = "run 'aws-ami -h' for how to use"
end
