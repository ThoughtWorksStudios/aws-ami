require 'aws-sdk'
require 'logger'

module AWS
  class AMI
    # name: AMI name
    # region: aws region of the new AMI
    # key_name: AWS EC2 ssh key name for accessing ec2 instance for debuging problems
    # install_script: a script file can be run on the ec2 instance that is launched from base ami to install packages
    # base_ami: a yml file describes base AMI used for building new AMI for each region
    # timeout: Timeout for running install script, default 600
    # publish_to_account: publish the AMI to this account if need
    # assume_yes: true for deleting stack when creating image failed
    def initialize(options={})
      @name = options[:name] || raise("Must have a name for the AMI")
      @region = options[:region] || raise("Must specify aws region")
      @key_name = options[:key_name] || raise("Please specify aws ssh key name, so that you can debug problem when something goes wrong")
      @install_script = File.read(options[:install_script]) || raise("Must provide install packages script file")

      @base_ami = YAML.load(File.read(options[:base_ami]))[@region] || raise("Must provide base ami yml file for each region")

      @timeout = options[:timeout] || '600'
      @assume_yes = options[:assume_yes] || false
      @publish_to_account = options[:publish_to_account]
      @test = options[:test]
    end

    def build
      stack = cloudformation.stacks.create("build-#{@name}-ami",
                                           load_formation,
                                           :disable_rollback => true,
                                           :parameters => {
                                             'Timeout' => @timeout,
                                             'KeyName' => @key_name,
                                             'InstallScript' => @install_script,
                                             "BaseAMI" => @base_ami
                                           })
      logger.info "creating stack for region #{@region}"
      wait_until_created(stack)
      begin
        instance_id = stack.resources['EC2Instance'].physical_resource_id
        instance = ec2.instances[instance_id]
        if @test
          puts "Build AMI Stack created"
          puts "EC2 instance dns name: #{instance.dns_name}, ip address: #{instance.ip_address}"
          puts "continue to create AMI Image? [y/n]"
          unless gets.strip == 'y'
            logger.info "delete stack and stop"
            stack.delete
            return
          end
          logger.info "continue to create image"
        end
        logger.info "creating image"
        image = instance.create_image(@name, :description => "Created at #{Time.now}")
        sleep 2 until image.exists?
        logger.info "image #{image.id} state: #{image.state}"
        sleep 5 until image.state != :pending
        if image.state == :failed
          raise "Create image failed"
        end

        logger.info "image created"
        logger.info "delete #{stack.name} stack"
        stack.delete
      rescue => e
        logger.error "Creating AMI failed #{e.message}"
        logger.error e.backtrace.join("\n")
        logger.info "delete #{stack.name}? [y/n]"
        if @assume_yes || gets.strip.downcase == 'y'
          logger.info 'delete stack'
          stack.delete
        else
          logger.info "left stack live"
        end
        raise e
      end
      if @publish_to_account
        logger.info "add permissions for #{@publish_to_account}"
        image.permissions.add(@publish_to_account.gsub(/-/, ''))
      end
      logger.info "Image #{@name}[#{image.id}] created"
    end

    private
    def ec2
      @ec2 ||= AWS::EC2.new(:ec2_endpoint => "ec2.#{@region}.amazonaws.com")
    end

    def cloudformation
      @cfm ||= AWS::CloudFormation.new(:cloud_formation_endpoint => "cloudformation.#{@region}.amazonaws.com")
    end

    def wait_until_created(stack)
      loop do
        case stack.status.to_s
        when /^create_complete$/i
          break
        when /^create_(failed|rollback_complete)$/i
          raise "Create Stack failed"
        end
        event = stack.events.first
        logger.info("latest event: #{event.resource_type} #{event.resource_status}")
        sleep 5
      end
    end

    def load_formation
      File.read(File.join(File.dirname(__FILE__), 'formation.json'))
    end

    def logger
      @logger ||= Logger.new(STDOUT)
    end
  end
end
