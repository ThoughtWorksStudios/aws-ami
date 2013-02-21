require 'aws-sdk'
require 'logger'

module AWS
  class AMI
    # region: aws region of the new AMI
    # assume_yes: true for deleting stack when creating image failed
    def initialize(options={})
      @assume_yes = options[:assume_yes]
      @region = options[:region]
      @publish_to_account = options[:publish_to_account]
    end

    # name: new AMI name, for example: mingle-saas-base
    # parameters:
    #   BaseAMI: the base AMI id for the new AMI, for example:
    #     "ami-0d153248" for the "ubuntu/images/ebs/ubuntu-precise-12.04-amd64-server-20121001" in us-west-1 region
    #   KeyName: the ssh key name for accessing the ec2 instance while building the AMI, this is only used when you need to debug problems
    #   InstallScript: the script installs everything need for the AMI, from 2048 to 16k bytes depending on the base ami provided
    def build(name, parameters)
      stack = cloudformation.stacks.create("build-#{name}-ami",
                                           load_formation,
                                           :disable_rollback => true,
                                           :parameters => parameters)
      logger.info "creating stack"
      wait_until_created(stack)
      begin
        instance_id = stack.resources['EC2Instance'].physical_resource_id

        logger.info "creating image"
        image = ec2.instances[instance_id].create_image(name, :description => "Created at #{Time.now}")
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
      logger.info "Image #{name}[#{image.id}] created"
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
