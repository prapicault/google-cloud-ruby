# Copyright 2014 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require "google/cloud/storage/bucket/acl"
require "google/cloud/storage/bucket/list"
require "google/cloud/storage/bucket/cors"
require "google/cloud/storage/bucket/lifecycle"
require "google/cloud/storage/convert"
require "google/cloud/storage/file"
require "google/cloud/storage/notification"
require "google/cloud/storage/policy"
require "google/cloud/storage/post_object"
require "pathname"

module Google
  module Cloud
    module Storage
      ##
      # # Bucket
      #
      # Represents a Storage bucket. Belongs to a Project and has many Files.
      #
      # @example
      #   require "google/cloud/storage"
      #
      #   storage = Google::Cloud::Storage.new
      #
      #   bucket = storage.bucket "my-bucket"
      #   file = bucket.file "path/to/my-file.ext"
      #
      class Bucket
        include Convert
        ##
        # @private Alias to the Google Client API module
        API = Google::Apis::StorageV1

        ##
        # @private The Service object.
        attr_accessor :service

        ##
        # @private The Google API Client object.
        attr_accessor :gapi

        ##
        # A boolean value or a project ID string to indicate the project to
        # be billed for operations on the bucket and its files. If this
        # attribute is set to `true`, transit costs for operations on the bucket
        # will be billed to the current project for this client. (See
        # {Project#project} for the ID of the current project.) If this
        # attribute is set to a project ID, and that project is authorized for
        # the currently authenticated service account, transit costs will be
        # billed to that project. This attribute is required with requester
        # pays-enabled buckets. The default is `nil`.
        #
        # In general, this attribute should be set when first retrieving the
        # bucket by providing the `user_project` option to {Project#bucket}.
        #
        # See also {#requester_pays=} and {#requester_pays}.
        #
        # @example Setting a non-default project:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "other-project-bucket", user_project: true
        #   files = bucket.files # Billed to current project
        #   bucket.user_project = "my-other-project"
        #   files = bucket.files # Billed to "my-other-project"
        #
        attr_accessor :user_project

        ##
        # @private Create an empty Bucket object.
        def initialize
          @service = nil
          @gapi = API::Bucket.new
          @user_project = nil
        end

        ##
        # The kind of item this is.
        # For buckets, this is always `storage#bucket`.
        #
        # @return [String]
        #
        def kind
          @gapi.kind
        end

        ##
        # The ID of the bucket.
        #
        # @return [String]
        #
        def id
          @gapi.id
        end

        ##
        # The name of the bucket.
        #
        # @return [String]
        #
        def name
          @gapi.name
        end

        ##
        # A URL that can be used to access the bucket using the REST API.
        #
        # @return [String]
        #
        def api_url
          @gapi.self_link
        end

        ##
        # Creation time of the bucket.
        #
        # @return [DateTime]
        #
        def created_at
          @gapi.time_created
        end

        ##
        # The metadata generation of the bucket.
        #
        # @return [Integer] The metageneration.
        #
        def metageneration
          @gapi.metageneration
        end

        ##
        # Returns the current CORS configuration for a static website served
        # from the bucket.
        #
        # The return value is a frozen (unmodifiable) array of hashes containing
        # the attributes specified for the Bucket resource field
        # [cors](https://cloud.google.com/storage/docs/json_api/v1/buckets#cors).
        #
        # This method also accepts a block for updating the bucket's CORS rules.
        # See {Bucket::Cors} for details.
        #
        # @see https://cloud.google.com/storage/docs/cross-origin Cross-Origin
        #   Resource Sharing (CORS)
        #
        # @yield [cors] a block for setting CORS rules
        # @yieldparam [Bucket::Cors] cors the object accepting CORS rules
        #
        # @return [Bucket::Cors] The frozen builder object.
        #
        # @example Retrieving the bucket's CORS rules.
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   bucket.cors.size #=> 2
        #   rule = bucket.cors.first
        #   rule.origin #=> ["http://example.org"]
        #   rule.methods #=> ["GET","POST","DELETE"]
        #   rule.headers #=> ["X-My-Custom-Header"]
        #   rule.max_age #=> 3600
        #
        # @example Updating the bucket's CORS rules inside a block.
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.update do |b|
        #     b.cors do |c|
        #       c.add_rule ["http://example.org", "https://example.org"],
        #                  "*",
        #                  headers: ["X-My-Custom-Header"],
        #                  max_age: 3600
        #     end
        #   end
        #
        def cors
          cors_builder = Bucket::Cors.from_gapi @gapi.cors_configurations
          if block_given?
            yield cors_builder
            if cors_builder.changed?
              @gapi.cors_configurations = cors_builder.to_gapi
              patch_gapi! :cors_configurations
            end
          end
          cors_builder.freeze # always return frozen objects
        end

        ##
        # Returns the current Object Lifecycle Management rules configuration
        # for the bucket.
        #
        # This method also accepts a block for updating the bucket's Object
        # Lifecycle Management rules. See {Bucket::Lifecycle} for details.
        #
        # @see https://cloud.google.com/storage/docs/lifecycle Object
        #   Lifecycle Management
        # @see https://cloud.google.com/storage/docs/managing-lifecycles
        #   Managing Object Lifecycles
        #
        # @yield [lifecycle] a block for setting Object Lifecycle Management
        #   rules
        # @yieldparam [Bucket::Lifecycle] lifecycle the object accepting Object
        #   Lifecycle Management rules
        #
        # @return [Bucket::Lifecycle] The frozen builder object.
        #
        # @example Retrieving a bucket's lifecycle management rules.
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.lifecycle.size #=> 2
        #   rule = bucket.lifecycle.first
        #   rule.action #=> "SetStorageClass"
        #   rule.storage_class #=> "COLDLINE"
        #   rule.age #=> 10
        #   rule.matches_storage_class #=> ["MULTI_REGIONAL", "REGIONAL"]
        #
        # @example Updating the bucket's lifecycle management rules in a block.
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.update do |b|
        #     b.lifecycle do |l|
        #       # Remove the last rule from the array
        #       l.pop
        #       # Remove rules with the given condition
        #       l.delete_if do |r|
        #         r.matches_storage_class.include? "NEARLINE"
        #       end
        #       # Update rules
        #       l.each do |r|
        #         r.age = 90 if r.action == "Delete"
        #       end
        #       # Add a rule
        #       l.add_set_storage_class_rule "COLDLINE", age: 10
        #     end
        #   end
        #
        def lifecycle
          lifecycle_builder = Bucket::Lifecycle.from_gapi @gapi.lifecycle
          if block_given?
            yield lifecycle_builder
            if lifecycle_builder.changed?
              @gapi.lifecycle = lifecycle_builder.to_gapi
              patch_gapi! :lifecycle
            end
          end
          lifecycle_builder.freeze # always return frozen objects
        end

        ##
        # The location of the bucket.
        # Object data for objects in the bucket resides in physical
        # storage within this region. Defaults to US.
        # See the developer's guide for the authoritative list.
        #
        # @return [String]
        #
        # @see https://cloud.google.com/storage/docs/concepts-techniques
        #
        def location
          @gapi.location
        end

        ##
        # The destination bucket name for the bucket's logs.
        #
        # @return [String]
        #
        # @see https://cloud.google.com/storage/docs/access-logs Access Logs
        #
        def logging_bucket
          @gapi.logging.log_bucket if @gapi.logging
        end

        ##
        # Updates the destination bucket for the bucket's logs.
        #
        # @see https://cloud.google.com/storage/docs/access-logs Access Logs
        #
        # @param [String] logging_bucket The bucket to hold the logging output
        #
        def logging_bucket= logging_bucket
          @gapi.logging ||= API::Bucket::Logging.new
          @gapi.logging.log_bucket = logging_bucket
          patch_gapi! :logging
        end

        ##
        # The logging object prefix for the bucket's logs. For more information,
        #
        # @see https://cloud.google.com/storage/docs/access-logs Access Logs
        #
        # @return [String]
        #
        def logging_prefix
          @gapi.logging.log_object_prefix if @gapi.logging
        end

        ##
        # Updates the logging object prefix. This prefix will be used to create
        # log object names for the bucket. It can be at most 900 characters and
        # must be a [valid object
        # name](https://cloud.google.com/storage/docs/bucket-naming#objectnames).
        # By default, the object prefix is the name of the bucket for which the
        # logs are enabled.
        #
        # @see https://cloud.google.com/storage/docs/access-logs Access Logs
        #
        # @param [String] logging_prefix The logging object prefix.
        #
        def logging_prefix= logging_prefix
          @gapi.logging ||= API::Bucket::Logging.new
          @gapi.logging.log_object_prefix = logging_prefix
          patch_gapi! :logging
        end

        ##
        # The bucket's storage class. This defines how objects in the bucket are
        # stored and determines the SLA and the cost of storage. Values include
        # `MULTI_REGIONAL`, `REGIONAL`, `NEARLINE`, `COLDLINE`, and
        # `DURABLE_REDUCED_AVAILABILITY`.
        #
        # @return [String]
        #
        def storage_class
          @gapi.storage_class
        end

        ##
        # Updates the bucket's storage class. This defines how objects in the
        # bucket are stored and determines the SLA and the cost of storage.
        # Accepted values include `:multi_regional`, `:regional`, `:nearline`,
        # and `:coldline`, as well as the equivalent strings returned by
        # {Bucket#storage_class}. For more information, see [Storage
        # Classes](https://cloud.google.com/storage/docs/storage-classes).
        #
        # @param [Symbol, String] new_storage_class Storage class of the bucket.
        #
        def storage_class= new_storage_class
          @gapi.storage_class = storage_class_for new_storage_class
          patch_gapi! :storage_class
        end

        ##
        # Whether [Object
        # Versioning](https://cloud.google.com/storage/docs/object-versioning)
        # is enabled for the bucket.
        #
        # @return [Boolean]
        #
        def versioning?
          @gapi.versioning.enabled? unless @gapi.versioning.nil?
        end

        ##
        # Updates whether [Object
        # Versioning](https://cloud.google.com/storage/docs/object-versioning)
        # is enabled for the bucket.
        #
        # @param [Boolean] new_versioning true if versioning is to be enabled
        #   for the bucket.
        #
        def versioning= new_versioning
          @gapi.versioning ||= API::Bucket::Versioning.new
          @gapi.versioning.enabled = new_versioning
          patch_gapi! :versioning
        end

        ##
        # The main page suffix for a static website. If the requested object
        # path is missing, the service will ensure the path has a trailing '/',
        # append this suffix, and attempt to retrieve the resulting object. This
        # allows the creation of index.html objects to represent directory
        # pages.
        #
        # @see https://cloud.google.com/storage/docs/website-configuration#step4
        #   How to Host a Static Website
        #
        # @return [String] The main page suffix.
        #
        def website_main
          @gapi.website.main_page_suffix if @gapi.website
        end

        ##
        # Updates the main page suffix for a static website.
        #
        # @see https://cloud.google.com/storage/docs/website-configuration#step4
        #   How to Host a Static Website
        #
        # @param [String] website_main The main page suffix.
        #
        def website_main= website_main
          @gapi.website ||= API::Bucket::Website.new
          @gapi.website.main_page_suffix = website_main
          patch_gapi! :website
        end

        ##
        # The page returned from a static website served from the bucket when a
        # site visitor requests a resource that does not exist.
        #
        # @see https://cloud.google.com/storage/docs/website-configuration#step4
        #   How to Host a Static Website
        #
        # @return [String]
        #
        def website_404
          @gapi.website.not_found_page if @gapi.website
        end

        ##
        # A hash of user-provided labels. The hash is frozen and changes are not
        # allowed.
        #
        # @return [Hash(String => String)]
        #
        def labels
          m = @gapi.labels
          m = m.to_h if m.respond_to? :to_h
          m.dup.freeze
        end

        ##
        # Updates the hash of user-provided labels.
        #
        # @param [Hash(String => String)] labels The user-provided labels.
        #
        def labels= labels
          @gapi.labels = labels
          patch_gapi! :labels
        end

        ##
        # Updates the page returned from a static website served from the bucket
        # when a site visitor requests a resource that does not exist.
        #
        # @see https://cloud.google.com/storage/docs/website-configuration#step4
        #   How to Host a Static Website
        #
        def website_404= website_404
          @gapi.website ||= API::Bucket::Website.new
          @gapi.website.not_found_page = website_404
          patch_gapi! :website
        end

        ##
        # Indicates that a client accessing the bucket or a file it contains
        # must assume the transit costs related to the access. The requester
        # must pass the `user_project` option to {Project#bucket} and
        # {Project#buckets} to indicate the project to which the access costs
        # should be billed.
        #
        # @return [Boolean, nil] Returns `true` if requester pays is enabled for
        #   the bucket.
        #
        def requester_pays
          @gapi.billing.requester_pays if @gapi.billing
        end
        alias requester_pays? requester_pays

        ##
        # Enables requester pays for the bucket. If enabled, a client accessing
        # the bucket or a file it contains must assume the transit costs related
        # to the access. The requester must pass the `user_project` option to
        # {Project#bucket} and {Project#buckets} to indicate the project to
        # which the access costs should be billed.
        #
        # @param [Boolean] new_requester_pays When set to `true`, requester pays
        #   is enabled for the bucket.
        #
        # @example Enable requester pays for a bucket:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.requester_pays = true # API call
        #   # Other projects must now provide `user_project` option when calling
        #   # Project#bucket or Project#buckets to access this bucket.
        #
        def requester_pays= new_requester_pays
          @gapi.billing ||= API::Bucket::Billing.new
          @gapi.billing.requester_pays = new_requester_pays
          patch_gapi! :billing
        end

        ##
        # The Cloud KMS encryption key that will be used to protect files.
        # For example: `projects/a/locations/b/keyRings/c/cryptoKeys/d`
        #
        # @return [String, nil] A Cloud KMS encryption key, or `nil` if none
        #   has been configured.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   # KMS key ring must use the same location as the bucket.
        #   kms_key_name = "projects/a/locations/b/keyRings/c/cryptoKeys/d"
        #   bucket.default_kms_key = kms_key_name
        #
        #   bucket.default_kms_key #=> kms_key_name
        #
        def default_kms_key
          @gapi.encryption && @gapi.encryption.default_kms_key_name
        end

        ##
        # Set the Cloud KMS encryption key that will be used to protect files.
        # For example: `projects/a/locations/b/keyRings/c/cryptoKeys/d`
        #
        # @param [String] new_default_kms_key New Cloud KMS key name.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   # KMS key ring must use the same location as the bucket.
        #   kms_key_name = "projects/a/locations/b/keyRings/c/cryptoKeys/d"
        #
        #   bucket.default_kms_key = kms_key_name
        #
        def default_kms_key= new_default_kms_key
          @gapi.encryption = API::Bucket::Encryption.new \
            default_kms_key_name: new_default_kms_key
          patch_gapi! :encryption
        end

        ##
        # The period of time (in seconds) that files in the bucket must be
        # retained, and cannot be deleted, overwritten, or archived.
        # The value must be between 0 and 100 years (in seconds.)
        #
        # See also: {#retention_period=}, {#retention_effective_at}, and
        # {#retention_policy_locked?}.
        #
        # @return [Integer, nil] The retention period defined in seconds, if a
        #   retention policy exists for the bucket.
        #
        def retention_period
          @gapi.retention_policy && @gapi.retention_policy.retention_period
        end

        ##
        # The period of time (in seconds) that files in the bucket must be
        # retained, and cannot be deleted, overwritten, or archived. Passing a
        # valid Integer value will add a new retention policy to the bucket
        # if none exists. Passing `nil` will remove the retention policy from
        # the bucket if it exists, unless the policy is locked.
        #
        # Locked policies can be extended in duration by using this method
        # to set a higher value. Such an extension is permanent, and it cannot
        # later be reduced.  The extended duration will apply retroactively to
        # all files currently in the bucket.
        #
        # See also: {#lock_retention_policy!}, {#retention_period},
        # {#retention_effective_at}, and {#retention_policy_locked?}.
        #
        # @param [Integer, nil] new_retention_period The retention period
        #   defined in seconds. The value must be between 0 and 100 years (in
        #   seconds), or `nil`.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.retention_period = 2592000 # 30 days in seconds
        #
        #   file = bucket.create_file "path/to/local.file.ext"
        #   file.delete # raises Google::Cloud::PermissionDeniedError
        #
        def retention_period= new_retention_period
          if new_retention_period.nil?
            @gapi.retention_policy = nil
          else
            @gapi.retention_policy ||= API::Bucket::RetentionPolicy.new
            @gapi.retention_policy.retention_period = new_retention_period
          end

          patch_gapi! :retention_policy
        end

        ##
        # The time from which the retention policy was effective. Whenever a
        # retention policy is created or extended, GCS updates the effective
        # date of the policy. The effective date signals the date starting from
        # which objects were guaranteed to be retained for the full duration of
        # the policy.
        #
        # This field is updated when the retention policy is created or
        # modified, including extension of a locked policy.
        #
        # @return [DateTime, nil] The effective date of the bucket's retention
        #   policy, if a policy exists.
        #
        def retention_effective_at
          @gapi.retention_policy && @gapi.retention_policy.effective_time
        end

        ##
        # Whether the bucket's file retention policy is locked and its retention
        # period cannot be reduced. See {#retention_period=} and
        # {#lock_retention_policy!}.
        #
        # This value can only be set to `true` by calling
        # {Bucket#lock_retention_policy!}.
        #
        # @return [Boolean] Returns `false` if there is no retention policy or
        #   if the retention policy is unlocked and the retention period can be
        #   reduced. Returns `true` if the retention policy is locked and the
        #   retention period cannot be reduced.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.retention_period = 2592000 # 30 days in seconds
        #   bucket.lock_retention_policy!
        #   bucket.retention_policy_locked? # true
        #
        #   file = bucket.create_file "path/to/local.file.ext"
        #   file.delete # raises Google::Cloud::PermissionDeniedError
        #
        def retention_policy_locked?
          return false unless @gapi.retention_policy
          !@gapi.retention_policy.is_locked.nil? &&
            @gapi.retention_policy.is_locked
        end

        ##
        # Whether the `event_based_hold` field for newly-created files in the
        # bucket will be initially set to `true`. See
        # {#default_event_based_hold=}, {File#event_based_hold?} and
        # {File#set_event_based_hold!}.
        #
        # @return [Boolean] Returns `true` if the `event_based_hold` field for
        #   newly-created files in the bucket will be initially set to `true`,
        #   otherwise `false`.
        #
        def default_event_based_hold?
          !@gapi.default_event_based_hold.nil? && @gapi.default_event_based_hold
        end

        ##
        # Updates the default event-based hold field for the bucket. This field
        # controls the initial state of the `event_based_hold` field for
        # newly-created files in the bucket.
        #
        # See {File#event_based_hold?} and {File#set_event_based_hold!}.
        #
        # @param [Boolean] new_default_event_based_hold The default event-based
        #   hold field for the bucket.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.update do |b|
        #     b.retention_period = 2592000 # 30 days in seconds
        #     b.default_event_based_hold = true
        #   end
        #
        #   file = bucket.create_file "path/to/local.file.ext"
        #   file.event_based_hold? # true
        #   file.delete # raises Google::Cloud::PermissionDeniedError
        #   file.release_event_based_hold!
        #
        #   # The end of the retention period is calculated from the time that
        #   # the event-based hold was released.
        #   file.retention_expires_at
        #
        def default_event_based_hold= new_default_event_based_hold
          @gapi.default_event_based_hold = new_default_event_based_hold
          patch_gapi! :default_event_based_hold
        end

        ##
        # PERMANENTLY locks the retention policy (see {#retention_period=}) on
        # the bucket if one exists. The policy is transitioned to a locked state
        # in which its duration cannot be reduced.
        #
        # Locked policies can be extended in duration by setting
        # {#retention_period=} to a higher value. Such an extension is
        # permanent, and it cannot later be reduced.  The extended duration will
        # apply retroactively to all files currently in the bucket.
        #
        # This method also [creates a
        # lien](https://cloud.google.com/resource-manager/reference/rest/v1/liens/create)
        # on the `resourcemanager.projects.delete` permission for the project
        # containing the bucket.
        #
        # The bucket's metageneration value is required for the lock policy API
        # call. Attempting to call this method on a bucket that was loaded with
        # the `skip_lookup: true` option will result in an error.
        #
        # @return [Boolean] Returns `true` if the lock operation is successful.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.retention_period = 2592000 # 30 days in seconds
        #   bucket.lock_retention_policy!
        #   bucket.retention_policy_locked? # true
        #
        #   file = bucket.create_file "path/to/local.file.ext"
        #   file.delete # raises Google::Cloud::PermissionDeniedError
        #
        #   # Locked policies can be extended in duration
        #   bucket.retention_period = 7776000 # 90 days in seconds
        #
        def lock_retention_policy!
          ensure_service!
          @gapi = service.lock_bucket_retention_policy \
            name, metageneration, user_project: user_project
          true
        end

        ##
        # Whether the bucket's file IAM configuration enables Bucket Policy
        # Only. The default is false. This value can be modified by calling
        # {Bucket#policy_only=}.
        #
        # If true, access checks only use bucket-level IAM policies or above,
        # all object ACLs within the bucket are no longer evaluated, and
        # access-control is configured solely through the bucket's IAM policy.
        # Any requests which attempt to use the ACL API to view or manipulate
        # ACLs will fail with 400 errors.
        #
        # @return [Boolean] Returns `false` if the bucket has no IAM
        #   configuration or if Bucket Policy Only is not enabled in the IAM
        #   configuration. Returns `true` if Bucket Policy Only is enabled in
        #   the IAM configuration.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.policy_only = true
        #   bucket.policy_only? # true
        #
        def policy_only?
          return false unless @gapi.iam_configuration &&
                              @gapi.iam_configuration.bucket_policy_only
          !@gapi.iam_configuration.bucket_policy_only.enabled.nil? &&
            @gapi.iam_configuration.bucket_policy_only.enabled
        end

        ##
        # If enabled, access checks only use bucket-level IAM policies or above,
        # all object ACLs within the bucket are no longer evaluated, and
        # access-control is configured solely through the bucket's IAM policy.
        # Any requests which attempt to use the ACL API to view or manipulate
        # ACLs will fail with 400 errors.
        #
        # @param [Boolean] new_policy_only When set to `true`, Bucket Policy
        #   Only is enabled in the bucket's IAM configuration.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.policy_only = true
        #   bucket.policy_only? # true
        #
        #   bucket.default_acl.public! # Google::Cloud::InvalidArgumentError
        #
        #   # The deadline for disabling Bucket Policy Only.
        #   puts bucket.policy_only_locked_at
        #
        def policy_only= new_policy_only
          @gapi.iam_configuration ||= API::Bucket::IamConfiguration.new \
            bucket_policy_only: \
              API::Bucket::IamConfiguration::BucketPolicyOnly.new
          @gapi.iam_configuration.bucket_policy_only.enabled = new_policy_only
          patch_gapi! :iam_configuration
        end

        ##
        # The deadline time for disabling Bucket Policy Only by calling
        # {Bucket#policy_only=}. After the locked time the Bucket Policy Only
        # setting cannot be changed from true to false. Corresponds to the
        # property `locked_time`.
        #
        # @return [DateTime, nil] The deadline time for changing
        #   {Bucket#policy_only=} from true to false, or `nil` if
        #   {Bucket#policy_only?} is false.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.policy_only = true
        #
        #   # The deadline for disabling Bucket Policy Only.
        #   puts bucket.policy_only_locked_at
        #
        def policy_only_locked_at
          return nil unless @gapi.iam_configuration &&
                            @gapi.iam_configuration.bucket_policy_only
          @gapi.iam_configuration.bucket_policy_only.locked_time
        end

        ##
        # Updates the bucket with changes made in the given block in a single
        # PATCH request. The following attributes may be set: {#cors},
        # {#logging_bucket=}, {#logging_prefix=}, {#versioning=},
        # {#website_main=}, {#website_404=}, and {#requester_pays=}.
        #
        # In addition, the #cors configuration accessible in the block is
        # completely mutable and will be included in the request. (See
        # {Bucket::Cors})
        #
        # @yield [bucket] a block yielding a delegate object for updating the
        #   file
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   bucket.update do |b|
        #     b.website_main = "index.html"
        #     b.website_404 = "not_found.html"
        #     b.cors[0].methods = ["GET","POST","DELETE"]
        #     b.cors[1].headers << "X-Another-Custom-Header"
        #   end
        #
        # @example New CORS rules can also be added in a nested block:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.update do |b|
        #     b.cors do |c|
        #       c.add_rule ["http://example.org", "https://example.org"],
        #                  "*",
        #                  headers: ["X-My-Custom-Header"],
        #                  max_age: 300
        #     end
        #   end
        #
        def update
          updater = Updater.new @gapi
          yield updater
          # Add check for mutable cors
          updater.check_for_changed_labels!
          updater.check_for_mutable_cors!
          updater.check_for_mutable_lifecycle!
          patch_gapi! updater.updates unless updater.updates.empty?
        end

        ##
        # Permanently deletes the bucket.
        # The bucket must be empty before it can be deleted.
        #
        # The API call to delete the bucket may be retried under certain
        # conditions. See {Google::Cloud#storage} to control this behavior.
        #
        # @return [Boolean] Returns `true` if the bucket was deleted.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #   bucket.delete
        #
        def delete
          ensure_service!
          service.delete_bucket name, user_project: user_project
          true
        end

        ##
        # Retrieves a list of files matching the criteria.
        #
        # @param [String] prefix Filter results to files whose names begin with
        #   this prefix.
        # @param [String] delimiter Returns results in a directory-like mode.
        #   `items` will contain only objects whose names, aside from the
        #   `prefix`, do not contain `delimiter`. Objects whose names, aside
        #   from the `prefix`, contain `delimiter` will have their name,
        #   truncated after the `delimiter`, returned in `prefixes`. Duplicate
        #   `prefixes` are omitted.
        # @param [String] token A previously-returned page token representing
        #   part of the larger set of results to view.
        # @param [Integer] max Maximum number of items plus prefixes to return.
        #   As duplicate prefixes are omitted, fewer total results may be
        #   returned than requested. The default value of this parameter is
        #   1,000 items.
        # @param [Boolean] versions If `true`, lists all versions of an object
        #   as distinct results. The default is `false`. For more information,
        #   see [Object Versioning
        #   ](https://cloud.google.com/storage/docs/object-versioning).
        #
        # @return [Array<Google::Cloud::Storage::File>] (See
        #   {Google::Cloud::Storage::File::List})
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #   files = bucket.files
        #   files.each do |file|
        #     puts file.name
        #   end
        #
        # @example Retrieve all files: (See {File::List#all})
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #   files = bucket.files
        #   files.all do |file|
        #     puts file.name
        #   end
        #
        def files prefix: nil, delimiter: nil, token: nil, max: nil,
                  versions: nil
          ensure_service!
          gapi = service.list_files name, prefix: prefix, delimiter: delimiter,
                                          token: token, max: max,
                                          versions: versions,
                                          user_project: user_project
          File::List.from_gapi gapi, service, name, prefix, delimiter, max,
                               versions, user_project: user_project
        end
        alias find_files files

        ##
        # Retrieves a file matching the path.
        #
        # If a [customer-supplied encryption
        # key](https://cloud.google.com/storage/docs/encryption#customer-supplied)
        # was used with {#create_file}, the `encryption_key` option must be
        # provided or else the file's CRC32C checksum and MD5 hash will not be
        # returned.
        #
        # @param [String] path Name (path) of the file.
        # @param [Integer] generation When present, selects a specific revision
        #   of this object. Default is the latest version.
        # @param [Boolean] skip_lookup Optionally create a Bucket object
        #   without verifying the bucket resource exists on the Storage service.
        #   Calls made on this object will raise errors if the bucket resource
        #   does not exist. Default is `false`.
        # @param [String] encryption_key Optional. The customer-supplied,
        #   AES-256 encryption key used to encrypt the file, if one was provided
        #   to {#create_file}. (Not used if `skip_lookup` is also set.)
        #
        # @return [Google::Cloud::Storage::File, nil] Returns nil if file does
        #   not exist
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   file = bucket.file "path/to/my-file.ext"
        #   puts file.name
        #
        def file path, generation: nil, skip_lookup: nil, encryption_key: nil
          ensure_service!
          if skip_lookup
            return File.new_lazy name, path, service,
                                 generation: generation,
                                 user_project: user_project
          end
          gapi = service.get_file name, path, generation: generation,
                                              key: encryption_key,
                                              user_project: user_project
          File.from_gapi gapi, service, user_project: user_project
        rescue Google::Cloud::NotFoundError
          nil
        end
        alias find_file file

        ##
        # Creates a new {File} object by providing a path to a local file (or
        # any File-like object such as StringIO) to upload, along with the path
        # at which to store it in the bucket.
        #
        # #### Customer-supplied encryption keys
        #
        # By default, Google Cloud Storage manages server-side encryption keys
        # on your behalf. However, a [customer-supplied encryption key](https://cloud.google.com/storage/docs/encryption#customer-supplied)
        # can be provided with the `encryption_key` option. If given, the same
        # key must be provided to subsequently download or copy the file. If you
        # use customer-supplied encryption keys, you must securely manage your
        # keys and ensure that they are not lost. Also, please note that file
        # metadata is not encrypted, with the exception of the CRC32C checksum
        # and MD5 hash. The names of files and buckets are also not encrypted,
        # and you can read or update the metadata of an encrypted file without
        # providing the encryption key.
        #
        # @param [String, ::File] file Path of the file on the filesystem to
        #   upload. Can be an File object, or File-like object such as StringIO.
        #   (If the object does not have path, a `path` argument must be also be
        #   provided.)
        # @param [String] path Path to store the file in Google Cloud Storage.
        # @param [String] acl A predefined set of access controls to apply to
        #   this file.
        #
        #   Acceptable values are:
        #
        #   * `auth`, `auth_read`, `authenticated`, `authenticated_read`,
        #     `authenticatedRead` - File owner gets OWNER access, and
        #     allAuthenticatedUsers get READER access.
        #   * `owner_full`, `bucketOwnerFullControl` - File owner gets OWNER
        #     access, and project team owners get OWNER access.
        #   * `owner_read`, `bucketOwnerRead` - File owner gets OWNER access,
        #     and project team owners get READER access.
        #   * `private` - File owner gets OWNER access.
        #   * `project_private`, `projectPrivate` - File owner gets OWNER
        #     access, and project team members get access according to their
        #     roles.
        #   * `public`, `public_read`, `publicRead` - File owner gets OWNER
        #     access, and allUsers get READER access.
        # @param [String] cache_control The
        #   [Cache-Control](https://tools.ietf.org/html/rfc7234#section-5.2)
        #   response header to be returned when the file is downloaded.
        # @param [String] content_disposition The
        #   [Content-Disposition](https://tools.ietf.org/html/rfc6266)
        #   response header to be returned when the file is downloaded.
        # @param [String] content_encoding The [Content-Encoding
        #   ](https://tools.ietf.org/html/rfc7231#section-3.1.2.2) response
        #   header to be returned when the file is downloaded. For example,
        #   `content_encoding: "gzip"` can indicate to clients that the uploaded
        #   data is gzip-compressed. However, there is no check to guarantee the
        #   specified `Content-Encoding` has actually been applied to the file
        #   data, and incorrectly specifying the file's encoding could lead
        #   to unintended behavior on subsequent download requests.
        # @param [String] content_language The
        #   [Content-Language](http://tools.ietf.org/html/bcp47) response
        #   header to be returned when the file is downloaded.
        # @param [String] content_type The
        #   [Content-Type](https://tools.ietf.org/html/rfc2616#section-14.17)
        #   response header to be returned when the file is downloaded.
        # @param [String] crc32c The CRC32c checksum of the file data, as
        #   described in [RFC 4960, Appendix
        #   B](http://tools.ietf.org/html/rfc4960#appendix-B).
        #   If provided, Cloud Storage will only create the file if the value
        #   matches the value calculated by the service. See
        #   [Validation](https://cloud.google.com/storage/docs/hashes-etags)
        #   for more information.
        # @param [String] md5 The MD5 hash of the file data. If provided, Cloud
        #   Storage will only create the file if the value matches the value
        #   calculated by the service. See
        #   [Validation](https://cloud.google.com/storage/docs/hashes-etags) for
        #   more information.
        # @param [Hash] metadata A hash of custom, user-provided web-safe keys
        #   and arbitrary string values that will returned with requests for the
        #   file as "x-goog-meta-" response headers.
        # @param [Symbol, String] storage_class Storage class of the file.
        #   Determines how the file is stored and determines the SLA and the
        #   cost of storage. Accepted values include `:multi_regional`,
        #   `:regional`, `:nearline`, and `:coldline`, as well as the equivalent
        #   strings returned by {#storage_class}. For more information, see
        #   [Storage Classes](https://cloud.google.com/storage/docs/storage-classes)
        #   and [Per-Object Storage
        #   Class](https://cloud.google.com/storage/docs/per-object-storage-class).
        #   The default value is the default storage class for the bucket.
        # @param [String] encryption_key Optional. A customer-supplied, AES-256
        #   encryption key that will be used to encrypt the file. Do not provide
        #   if `kms_key` is used.
        # @param [String] kms_key Optional. Resource name of the Cloud KMS
        #   key, of the form
        #   `projects/my-prj/locations/kr-loc/keyRings/my-kr/cryptoKeys/my-key`,
        #   that will be used to encrypt the file. The KMS key ring must use
        #   the same location as the bucket.The Service Account associated with
        #   your project requires access to this encryption key. Do not provide
        #   if `encryption_key` is used.
        #
        # @return [Google::Cloud::Storage::File]
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.create_file "path/to/local.file.ext"
        #
        # @example Specifying a destination path:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.create_file "path/to/local.file.ext",
        #                      "destination/path/file.ext"
        #
        # @example Providing a customer-supplied encryption key:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #   bucket = storage.bucket "my-bucket"
        #
        #   # Key generation shown for example purposes only. Write your own.
        #   cipher = OpenSSL::Cipher.new "aes-256-cfb"
        #   cipher.encrypt
        #   key = cipher.random_key
        #
        #   bucket.create_file "path/to/local.file.ext",
        #                      "destination/path/file.ext",
        #                      encryption_key: key
        #
        #   # Store your key and hash securely for later use.
        #   file = bucket.file "destination/path/file.ext",
        #                      encryption_key: key
        #
        # @example Providing a customer-managed Cloud KMS encryption key:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #   bucket = storage.bucket "my-bucket"
        #
        #   # KMS key ring must use the same location as the bucket.
        #   kms_key_name = "projects/a/locations/b/keyRings/c/cryptoKeys/d"
        #
        #   bucket.create_file "path/to/local.file.ext",
        #                      "destination/path/file.ext",
        #                      kms_key: kms_key_name
        #
        #   file = bucket.file "destination/path/file.ext"
        #   file.kms_key #=> kms_key_name
        #
        # @example Create a file with gzip-encoded data.
        #   require "zlib"
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   gz = StringIO.new ""
        #   z = Zlib::GzipWriter.new gz
        #   z.write "Hello world!"
        #   z.close
        #   data = StringIO.new gz.string
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   bucket.create_file data, "path/to/gzipped.txt",
        #                      content_encoding: "gzip"
        #
        #   file = bucket.file "path/to/gzipped.txt"
        #
        #   # The downloaded data is decompressed by default.
        #   file.download "path/to/downloaded/hello.txt"
        #
        #   # The downloaded data remains compressed with skip_decompress.
        #   file.download "path/to/downloaded/gzipped.txt",
        #                 skip_decompress: true
        #
        def create_file file, path = nil, acl: nil, cache_control: nil,
                        content_disposition: nil, content_encoding: nil,
                        content_language: nil, content_type: nil,
                        crc32c: nil, md5: nil, metadata: nil,
                        storage_class: nil, encryption_key: nil, kms_key: nil,
                        temporary_hold: nil, event_based_hold: nil
          ensure_service!
          options = { acl: File::Acl.predefined_rule_for(acl), md5: md5,
                      cache_control: cache_control, content_type: content_type,
                      content_disposition: content_disposition, crc32c: crc32c,
                      content_encoding: content_encoding, metadata: metadata,
                      content_language: content_language, key: encryption_key,
                      kms_key: kms_key,
                      storage_class: storage_class_for(storage_class),
                      temporary_hold: temporary_hold,
                      event_based_hold: event_based_hold,
                      user_project: user_project }
          ensure_io_or_file_exists! file
          path ||= file.path if file.respond_to? :path
          path ||= file if file.is_a? String
          raise ArgumentError, "must provide path" if path.nil?

          gapi = service.insert_file name, file, path, options
          File.from_gapi gapi, service, user_project: user_project
        end
        alias upload_file create_file
        alias new_file create_file

        ##
        # Concatenates a list of existing files in the bucket into a new file in
        # the bucket. There is a limit (currently 32) to the number of files
        # that can be composed in a single operation.
        #
        # To compose files encrypted with a customer-supplied encryption key,
        # use the `encryption_key` option. All source files must have been
        # encrypted with the same key, and the resulting destination file will
        # also be encrypted with the same key.
        #
        # @param [Array<String, Google::Cloud::Storage::File>] sources The list
        #   of source file names or objects that will be concatenated into a
        #   single file.
        # @param [String] destination The name of the new file.
        # @param [String] acl A predefined set of access controls to apply to
        #   this file.
        #
        #   Acceptable values are:
        #
        #   * `auth`, `auth_read`, `authenticated`, `authenticated_read`,
        #     `authenticatedRead` - File owner gets OWNER access, and
        #     allAuthenticatedUsers get READER access.
        #   * `owner_full`, `bucketOwnerFullControl` - File owner gets OWNER
        #     access, and project team owners get OWNER access.
        #   * `owner_read`, `bucketOwnerRead` - File owner gets OWNER access,
        #     and project team owners get READER access.
        #   * `private` - File owner gets OWNER access.
        #   * `project_private`, `projectPrivate` - File owner gets OWNER
        #     access, and project team members get access according to their
        #     roles.
        #   * `public`, `public_read`, `publicRead` - File owner gets OWNER
        #     access, and allUsers get READER access.
        #
        # @param [String, nil] encryption_key Optional. The customer-supplied,
        #   AES-256 encryption key used to encrypt the source files, if one was
        #   used. All source files must have been encrypted with the same key,
        #   and the resulting destination file will also be encrypted with the
        #   key.
        #
        # @yield [file] A block yielding a delegate file object for setting the
        #   properties of the destination file.
        #
        # @return [Google::Cloud::Storage::File] The new file.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   sources = ["path/to/my-file-1.ext", "path/to/my-file-2.ext"]
        #
        #   new_file = bucket.compose sources, "path/to/new-file.ext"
        #
        # @example Set the properties of the new file in a block:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   sources = ["path/to/my-file-1.ext", "path/to/my-file-2.ext"]
        #
        #   new_file = bucket.compose sources, "path/to/new-file.ext" do |f|
        #     f.cache_control = "private, max-age=0, no-cache"
        #     f.content_disposition = "inline; filename=filename.ext"
        #     f.content_encoding = "deflate"
        #     f.content_language = "de"
        #     f.content_type = "application/json"
        #   end
        #
        # @example Specify the generation of source files (but skip retrieval):
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   file_1 = bucket.file "path/to/my-file-1.ext",
        #                        generation: 1490390259479000, skip_lookup: true
        #   file_2 = bucket.file "path/to/my-file-2.ext",
        #                        generation: 1490310974144000, skip_lookup: true
        #
        #   new_file = bucket.compose [file_1, file_2], "path/to/new-file.ext"
        #
        def compose sources, destination, acl: nil, encryption_key: nil
          ensure_service!
          sources = Array sources
          if sources.size < 2
            raise ArgumentError, "must provide at least two source files"
          end

          options = { acl: File::Acl.predefined_rule_for(acl),
                      key: encryption_key,
                      user_project: user_project }
          destination_gapi = nil
          if block_given?
            destination_gapi = API::Object.new
            updater = File::Updater.new destination_gapi
            yield updater
            updater.check_for_changed_metadata!
          end
          gapi = service.compose_file name, sources, destination,
                                      destination_gapi, options
          File.from_gapi gapi, service, user_project: user_project
        end
        alias compose_file compose
        alias combine compose

        ##
        # Generates a signed URL. See [Signed
        # URLs](https://cloud.google.com/storage/docs/access-control/signed-urls)
        # for more information.
        #
        # Generating a signed URL requires service account credentials, either
        # by connecting with a service account when calling
        # {Google::Cloud.storage}, or by passing in the service account `issuer`
        # and `signing_key` values. Although the private key can be passed as a
        # string for convenience, creating and storing an instance of
        # `OpenSSL::PKey::RSA` is more efficient when making multiple calls to
        # `signed_url`.
        #
        # A {SignedUrlUnavailable} is raised if the service account credentials
        # are missing. Service account credentials are acquired by following the
        # steps in [Service Account Authentication](
        # https://cloud.google.com/storage/docs/authentication#service_accounts).
        #
        # @see https://cloud.google.com/storage/docs/access-control/signed-urls
        #   Signed URLs guide
        # @see https://cloud.google.com/storage/docs/access-control/signed-urls#signing-resumable
        #   Using signed URLs with resumable uploads
        #
        # @param [String, nil] path Path to the file in Google Cloud Storage, or
        #   `nil` to generate a URL for listing all files in the bucket.
        # @param [String] method The HTTP verb to be used with the signed URL.
        #   Signed URLs can be used
        #   with `GET`, `HEAD`, `PUT`, and `DELETE` requests. Default is `GET`.
        # @param [Integer] expires The number of seconds until the URL expires.
        #   If the `version` is `:v2`, the default is 300 (5 minutes). If the
        #   `version` is `:v4`, the default is 604800 (7 days).
        # @param [String] content_type When provided, the client (browser) must
        #   send this value in the HTTP header. e.g. `text/plain`. This param is
        #   not used if the `version` is `:v4`.
        # @param [String] content_md5 The MD5 digest value in base64. If you
        #   provide this in the string, the client (usually a browser) must
        #   provide this HTTP header with this same value in its request. This
        #   param is not used if the `version` is `:v4`.
        # @param [Hash] headers Google extension headers (custom HTTP headers
        #   that begin with `x-goog-`) that must be included in requests that
        #   use the signed URL.
        # @param [String] issuer Service Account's Client Email.
        # @param [String] client_email Service Account's Client Email.
        # @param [OpenSSL::PKey::RSA, String] signing_key Service Account's
        #   Private Key.
        # @param [OpenSSL::PKey::RSA, String] private_key Service Account's
        #   Private Key.
        # @param [Hash] query Query string parameters to include in the signed
        #   URL. The given parameters are not verified by the signature.
        #
        #   Parameters such as `response-content-disposition` and
        #   `response-content-type` can alter the behavior of the response when
        #   using the URL, but only when the file resource is missing the
        #   corresponding values. (These values can be permanently set using
        #   {File#content_disposition=} and {File#content_type=}.)
        # @param [Symbol, String] version The version of the signed credential
        #   to create. Must be one of `:v2` or `:v4`. The default value is
        #   `:v2`.
        #
        # @return [String]
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   shared_url = bucket.signed_url "avatars/heidi/400x400.png"
        #
        # @example Using the `expires` and `version` options:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   shared_url = bucket.signed_url "avatars/heidi/400x400.png",
        #                                  expires: 300, # 5 minutes from now
        #                                  version: :v4
        #
        # @example Using the `issuer` and `signing_key` options:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   key = OpenSSL::PKey::RSA.new "-----BEGIN PRIVATE KEY-----\n..."
        #   shared_url = bucket.signed_url "avatars/heidi/400x400.png",
        #                                  issuer: "service-account@gcloud.com",
        #                                  signing_key: key
        #
        # @example Using the `headers` option:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   shared_url = bucket.signed_url "avatars/heidi/400x400.png",
        #                                  headers: {
        #                                    "x-goog-acl" => "private",
        #                                    "x-goog-meta-foo" => "bar,baz"
        #                                  }
        #
        # @example Generating a signed URL for resumable upload:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   url = bucket.signed_url "avatars/heidi/400x400.png",
        #                           method: "POST",
        #                           content_type: "image/png",
        #                           headers: {
        #                             "x-goog-resumable" => "start"
        #                           }
        #   # Send the `x-goog-resumable:start` header and the content type
        #   # with the resumable upload POST request.
        #
        # @example Omitting `path` for a URL to list all files in the bucket.
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   list_files_url = bucket.signed_url version: :v4
        #
        def signed_url path = nil, method: nil, expires: nil, content_type: nil,
                       content_md5: nil, headers: nil, issuer: nil,
                       client_email: nil, signing_key: nil, private_key: nil,
                       query: nil, version: nil
          ensure_service!
          version ||= :v2
          case version.to_sym
          when :v2
            signer = File::SignerV2.from_bucket self, path
            signer.signed_url method: method, expires: expires,
                              headers: headers, content_type: content_type,
                              content_md5: content_md5, issuer: issuer,
                              client_email: client_email,
                              signing_key: signing_key,
                              private_key: private_key, query: query
          when :v4
            signer = File::SignerV4.from_bucket self, path
            signer.signed_url method: method, expires: expires,
                              headers: headers, issuer: issuer,
                              client_email: client_email,
                              signing_key: signing_key,
                              private_key: private_key, query: query
          else
            raise ArgumentError, "version '#{version}' not supported"
          end
        end

        ##
        # Generate a PostObject that includes the fields and url to
        # upload objects via html forms.
        #
        # Generating a PostObject requires service account credentials,
        # either by connecting with a service account when calling
        # {Google::Cloud.storage}, or by passing in the service account
        # `issuer` and `signing_key` values. Although the private key can
        # be passed as a string for convenience, creating and storing
        # an instance of # `OpenSSL::PKey::RSA` is more efficient
        # when making multiple calls to `post_object`.
        #
        # A {SignedUrlUnavailable} is raised if the service account credentials
        # are missing. Service account credentials are acquired by following the
        # steps in [Service Account Authentication](
        # https://cloud.google.com/storage/docs/authentication#service_accounts).
        #
        # @see https://cloud.google.com/storage/docs/xml-api/post-object
        #
        # @param [String] path Path to the file in Google Cloud Storage.
        # @param [Hash] policy The security policy that describes what
        #   can and cannot be uploaded in the form. When provided,
        #   the PostObject fields will include a Signature based on the JSON
        #   representation of this Hash and the same policy in Base64 format.
        #   If you do not provide a security policy, requests are considered
        #   to be anonymous and will only work with buckets that have granted
        #   WRITE or FULL_CONTROL permission to anonymous users.
        #   See [Policy Document](https://cloud.google.com/storage/docs/xml-api/post-object#policydocument)
        #   for more information.
        # @param [String] issuer Service Account's Client Email.
        # @param [String] client_email Service Account's Client Email.
        # @param [OpenSSL::PKey::RSA, String] signing_key Service Account's
        #   Private Key.
        # @param [OpenSSL::PKey::RSA, String] private_key Service Account's
        #   Private Key.
        #
        # @return [PostObject]
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   post = bucket.post_object "avatars/heidi/400x400.png"
        #
        #   post.url #=> "https://storage.googleapis.com"
        #   post.fields[:key] #=> "my-todo-app/avatars/heidi/400x400.png"
        #   post.fields[:GoogleAccessId] #=> "0123456789@gserviceaccount.com"
        #   post.fields[:signature] #=> "ABC...XYZ="
        #   post.fields[:policy] #=> "ABC...XYZ="
        #
        # @example Using a policy to define the upload authorization:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   policy = {
        #     expiration: (Time.now + 3600).iso8601,
        #     conditions: [
        #       ["starts-with", "$key", ""],
        #       {acl: "bucket-owner-read"},
        #       {bucket: "travel-maps"},
        #       {success_action_redirect: "http://example.com/success.html"},
        #       ["eq", "$Content-Type", "image/jpeg"],
        #       ["content-length-range", 0, 1000000]
        #     ]
        #   }
        #
        #   bucket = storage.bucket "my-todo-app"
        #   post = bucket.post_object "avatars/heidi/400x400.png",
        #                              policy: policy
        #
        #   post.url #=> "https://storage.googleapis.com"
        #   post.fields[:key] #=> "my-todo-app/avatars/heidi/400x400.png"
        #   post.fields[:GoogleAccessId] #=> "0123456789@gserviceaccount.com"
        #   post.fields[:signature] #=> "ABC...XYZ="
        #   post.fields[:policy] #=> "ABC...XYZ="
        #
        # @example Using the issuer and signing_key options:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #   key = OpenSSL::PKey::RSA.new
        #   post = bucket.post_object "avatars/heidi/400x400.png",
        #                             issuer: "service-account@gcloud.com",
        #                             signing_key: key
        #
        #   post.url #=> "https://storage.googleapis.com"
        #   post.fields[:key] #=> "my-todo-app/avatars/heidi/400x400.png"
        #   post.fields[:GoogleAccessId] #=> "0123456789@gserviceaccount.com"
        #   post.fields[:signature] #=> "ABC...XYZ="
        #   post.fields[:policy] #=> "ABC...XYZ="
        #
        def post_object path, policy: nil, issuer: nil,
                        client_email: nil, signing_key: nil,
                        private_key: nil
          ensure_service!

          signer = File::SignerV2.from_bucket self, path
          signer.post_object issuer: issuer, client_email: client_email,
                             signing_key: signing_key, private_key: private_key,
                             policy: policy
        end

        ##
        # The {Bucket::Acl} instance used to control access to the bucket.
        #
        # A bucket has owners, writers, and readers. Permissions can be granted
        # to an individual user's email address, a group's email address, as
        # well as many predefined lists.
        #
        # @see https://cloud.google.com/storage/docs/access-control Access
        #   Control guide
        #
        # @return [Bucket::Acl]
        #
        # @example Grant access to a user by prepending `"user-"` to an email:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   email = "heidi@example.net"
        #   bucket.acl.add_reader "user-#{email}"
        #
        # @example Grant access to a group by prepending `"group-"` to an email:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   email = "authors@example.net"
        #   bucket.acl.add_reader "group-#{email}"
        #
        # @example Or, grant access via a predefined permissions list:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.acl.public!
        #
        def acl
          @acl ||= Bucket::Acl.new self
        end

        ##
        # The {Bucket::DefaultAcl} instance used to control access to the
        # bucket's files.
        #
        # A bucket's files have owners, writers, and readers. Permissions can be
        # granted to an individual user's email address, a group's email
        # address, as well as many predefined lists.
        #
        # @see https://cloud.google.com/storage/docs/access-control Access
        #   Control guide
        #
        # @return [Bucket::DefaultAcl]
        #
        # @example Grant access to a user by prepending `"user-"` to an email:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   email = "heidi@example.net"
        #   bucket.default_acl.add_reader "user-#{email}"
        #
        # @example Grant access to a group by prepending `"group-"` to an email
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   email = "authors@example.net"
        #   bucket.default_acl.add_reader "group-#{email}"
        #
        # @example Or, grant access via a predefined permissions list:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.default_acl.public!
        #
        def default_acl
          @default_acl ||= Bucket::DefaultAcl.new self
        end

        ##
        # Gets and updates the [Cloud IAM](https://cloud.google.com/iam/) access
        # control policy for this bucket.
        #
        # @see https://cloud.google.com/iam/docs/managing-policies Managing
        #   Policies
        # @see https://cloud.google.com/storage/docs/json_api/v1/buckets/setIamPolicy
        #   Buckets: setIamPolicy
        #
        # @param [Boolean] force [Deprecated] Force the latest policy to be
        #   retrieved from the Storage service when `true`. Deprecated because
        #   the latest policy is now always retrieved. The default is `nil`.
        #
        # @yield [policy] A block for updating the policy. The latest policy
        #   will be read from the service and passed to the block. After the
        #   block completes, the modified policy will be written to the service.
        # @yieldparam [Policy] policy the current Cloud IAM Policy for this
        #   bucket
        #
        # @return [Policy] the current Cloud IAM Policy for this bucket
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   policy = bucket.policy
        #
        # @example Retrieve the latest policy and update it in a block:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.policy do |p|
        #     p.add "roles/owner", "user:owner@example.com"
        #   end
        #
        def policy force: nil
          warn "DEPRECATED: 'force' in Bucket#policy" unless force.nil?
          ensure_service!
          gapi = service.get_bucket_policy name, user_project: user_project
          policy = Policy.from_gapi gapi
          return policy unless block_given?
          yield policy
          update_policy policy
        end

        ##
        # Updates the [Cloud IAM](https://cloud.google.com/iam/) access control
        # policy for this bucket. The policy should be read from {#policy}. See
        # {Google::Cloud::Storage::Policy} for an explanation of the
        # policy `etag` property and how to modify policies.
        #
        # You can also update the policy by passing a block to {#policy}, which
        # will call this method internally after the block completes.
        #
        # @see https://cloud.google.com/iam/docs/managing-policies Managing
        #   Policies
        # @see https://cloud.google.com/storage/docs/json_api/v1/buckets/setIamPolicy
        #   Buckets: setIamPolicy
        #
        # @param [Policy] new_policy a new or modified Cloud IAM Policy for this
        #   bucket
        #
        # @return [Policy] The policy returned by the API update operation.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   policy = bucket.policy # API call
        #
        #   policy.add "roles/owner", "user:owner@example.com"
        #
        #   bucket.update_policy policy # API call
        #
        def update_policy new_policy
          ensure_service!
          gapi = service.set_bucket_policy name, new_policy.to_gapi,
                                           user_project: user_project
          Policy.from_gapi gapi
        end
        alias policy= update_policy

        ##
        # Tests the specified permissions against the [Cloud
        # IAM](https://cloud.google.com/iam/) access control policy.
        #
        # @see https://cloud.google.com/iam/docs/managing-policies Managing
        #   Policies
        #
        # @param [String, Array<String>] permissions The set of permissions
        #   against which to check access. Permissions must be of the format
        #   `storage.resource.capability`, where resource is one of `buckets` or
        #   `objects`.
        #
        # @return [Array<String>] The permissions held by the caller.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   permissions = bucket.test_permissions "storage.buckets.get",
        #                                         "storage.buckets.delete"
        #   permissions.include? "storage.buckets.get"    #=> true
        #   permissions.include? "storage.buckets.delete" #=> false
        #
        def test_permissions *permissions
          permissions = Array(permissions).flatten
          ensure_service!
          gapi = service.test_bucket_permissions name, permissions,
                                                 user_project: user_project
          gapi.permissions
        end

        ##
        # Retrieves the entire list of Pub/Sub notification subscriptions for
        # the bucket.
        #
        # @see https://cloud.google.com/storage/docs/pubsub-notifications Cloud
        #   Pub/Sub Notifications for Google Cloud
        #
        # @return [Array<Google::Cloud::Storage::Notification>]
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #   notifications = bucket.notifications
        #   notifications.each do |notification|
        #     puts notification.id
        #   end
        #
        def notifications
          ensure_service!
          gapi = service.list_notifications name, user_project: user_project
          Array(gapi.items).map do |gapi_object|
            Notification.from_gapi name, gapi_object, service,
                                   user_project: user_project
          end
        end
        alias find_notifications notifications

        ##
        # Retrieves a Pub/Sub notification subscription for the bucket.
        #
        # @see https://cloud.google.com/storage/docs/pubsub-notifications Cloud
        #   Pub/Sub Notifications for Google Cloud
        #
        # @param [String] id The Notification ID.
        #
        # @return [Google::Cloud::Storage::Notification, nil] Returns nil if the
        #   notification does not exist
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   notification = bucket.notification "1"
        #   puts notification.id
        #
        def notification id
          ensure_service!
          gapi = service.get_notification name, id, user_project: user_project
          Notification.from_gapi name, gapi, service, user_project: user_project
        rescue Google::Cloud::NotFoundError
          nil
        end
        alias find_notification notification


        ##
        # Creates a new Pub/Sub notification subscription for the bucket.
        #
        # @see https://cloud.google.com/storage/docs/pubsub-notifications Cloud
        #   Pub/Sub Notifications for Google Cloud
        #
        # @param [String] topic The name of the Cloud PubSub topic to which the
        #   notification subscription will publish.
        # @param [Hash(String => String)] custom_attrs The custom attributes for
        #   the notification. An optional list of additional attributes to
        #   attach to each Cloud Pub/Sub message published for the notification
        #   subscription.
        # @param [Symbol, String, Array<Symbol, String>] event_types The event
        #   types for the notification subscription. If provided, messages will
        #   only be sent for the listed event types. If empty, messages will be
        #   sent for all event types.
        #
        #   Acceptable values are:
        #
        #   * `:finalize` - Sent when a new object (or a new generation of
        #     an existing object) is successfully created in the bucket. This
        #     includes copying or rewriting an existing object. A failed upload
        #     does not trigger this event.
        #   * `:update` - Sent when the metadata of an existing object changes.
        #   * `:delete` - Sent when an object has been permanently deleted. This
        #     includes objects that are overwritten or are deleted as part of
        #     the bucket's lifecycle configuration. For buckets with object
        #     versioning enabled, this is not sent when an object is archived
        #     (see `OBJECT_ARCHIVE`), even if archival occurs via the
        #     {File#delete} method.
        #   * `:archive` - Only sent when the bucket has enabled object
        #     versioning. This event indicates that the live version of an
        #     object has become an archived version, either because it was
        #     archived or because it was overwritten by the upload of an object
        #     of the same name.
        # @param [String] prefix The file name prefix for the notification
        #   subscription. If provided, the notification will only be applied to
        #   file names that begin with this prefix.
        # @param [Symbol, String, Boolean] payload The desired content of the
        #   Pub/Sub message payload. Acceptable values are:
        #
        #   * `:json` or `true` - The Pub/Sub message payload will be a UTF-8
        #     string containing the [resource
        #     representation](https://cloud.google.com/storage/docs/json_api/v1/objects#resource-representations)
        #     of the file's metadata.
        #   * `:none` or `false` - No payload is included with the notification.
        #
        #   The default value is `:json`.
        #
        # @return [Google::Cloud::Storage::Notification]
        #
        # @example
        #   require "google/cloud/pubsub"
        #   require "google/cloud/storage"
        #
        #   pubsub = Google::Cloud::Pubsub.new
        #   storage = Google::Cloud::Storage.new
        #
        #   topic = pubsub.create_topic "my-topic"
        #   topic.policy do |p|
        #     p.add "roles/pubsub.publisher",
        #           "serviceAccount:#{storage.service_account_email}"
        #   end
        #
        #   bucket = storage.bucket "my-bucket"
        #
        #   notification = bucket.create_notification topic.name
        #
        def create_notification topic, custom_attrs: nil, event_types: nil,
                                prefix: nil, payload: nil
          ensure_service!
          options = { custom_attrs: custom_attrs, event_types: event_types,
                      prefix: prefix, payload: payload,
                      user_project: user_project }

          gapi = service.insert_notification name, topic, options
          Notification.from_gapi name, gapi, service, user_project: user_project
        end
        alias new_notification create_notification

        ##
        # Reloads the bucket with current data from the Storage service.
        #
        def reload!
          ensure_service!
          @gapi = service.get_bucket name, user_project: user_project
          # If NotFound then lazy will never be unset
          @lazy = nil
          self
        end
        alias refresh! reload!

        ##
        # Determines whether the bucket exists in the Storage service.
        #
        # @return [Boolean] true if the bucket exists in the Storage service.
        #
        def exists?
          # Always true if we have a grpc object
          return true unless lazy?
          # If we have a value, return it
          return @exists unless @exists.nil?
          ensure_gapi!
          @exists = true
        rescue Google::Cloud::NotFoundError
          @exists = false
        end

        ##
        # @private
        # Determines whether the bucket was created without retrieving the
        # resource record from the API.
        def lazy?
          @lazy
        end

        ##
        # @private New Bucket from a Google API Client object.
        def self.from_gapi gapi, service, user_project: nil
          new.tap do |b|
            b.gapi = gapi
            b.service = service
            b.user_project = user_project
          end
        end

        ##
        # @private New lazy Bucket object without making an HTTP request.
        def self.new_lazy name, service, user_project: nil
          # TODO: raise if name is nil?
          new.tap do |b|
            b.gapi.name = name
            b.service = service
            b.user_project = user_project
            b.instance_variable_set :@lazy, true
          end
        end

        protected

        ##
        # Raise an error unless an active service is available.
        def ensure_service!
          raise "Must have active connection" unless service
        end

        ##
        # Ensures the Google::Apis::StorageV1::Bucket object exists.
        def ensure_gapi!
          ensure_service!
          return unless lazy?
          reload!
        end

        def patch_gapi! *attributes
          attributes.flatten!
          return if attributes.empty?
          ensure_service!
          patch_args = Hash[attributes.map do |attr|
            [attr, @gapi.send(attr)]
          end]
          patch_gapi = API::Bucket.new patch_args
          @gapi = service.patch_bucket name, patch_gapi,
                                       user_project: user_project
          @lazy = nil
          self
        end

        ##
        # Raise an error if the file is not found.
        def ensure_io_or_file_exists! file
          return if file.respond_to?(:read) && file.respond_to?(:rewind)
          return if ::File.file? file
          raise ArgumentError, "cannot find file #{file}"
        end

        ##
        # Yielded to a block to accumulate changes for a patch request.
        class Updater < Bucket
          attr_reader :updates
          ##
          # Create an Updater object.
          def initialize gapi
            @updates = []
            @gapi = gapi
            @labels = @gapi.labels.to_h.dup
            @cors_builder = nil
            @lifecycle_builder = nil
          end

          ##
          # A hash of user-provided labels. Changes are allowed.
          #
          # @return [Hash(String => String)]
          #
          def labels
            @labels
          end

          ##
          # Updates the hash of user-provided labels.
          #
          # @param [Hash(String => String)] labels The user-provided labels.
          #
          def labels= labels
            @labels = labels
            @gapi.labels = @labels
            patch_gapi! :labels
          end

          ##
          # @private Make sure any labels changes are saved
          def check_for_changed_labels!
            return if @labels == @gapi.labels.to_h
            @gapi.labels = @labels
            patch_gapi! :labels
          end

          def cors
            # Same as Bucket#cors, but not frozen
            @cors_builder ||= Bucket::Cors.from_gapi @gapi.cors_configurations
            yield @cors_builder if block_given?
            @cors_builder
          end

          ##
          # @private Make sure any cors changes are saved
          def check_for_mutable_cors!
            return if @cors_builder.nil?
            return unless @cors_builder.changed?
            @gapi.cors_configurations = @cors_builder.to_gapi
            patch_gapi! :cors_configurations
          end

          def lifecycle
            # Same as Bucket#lifecycle, but not frozen
            @lifecycle_builder ||= Bucket::Lifecycle.from_gapi @gapi.lifecycle
            yield @lifecycle_builder if block_given?
            @lifecycle_builder
          end

          ##
          # @private Make sure any lifecycle changes are saved
          def check_for_mutable_lifecycle!
            return if @lifecycle_builder.nil?
            return unless @lifecycle_builder.changed?
            @gapi.lifecycle = @lifecycle_builder.to_gapi
            patch_gapi! :lifecycle
          end

          protected

          ##
          # Queue up all the updates instead of making them.
          def patch_gapi! attribute
            @updates << attribute
            @updates.uniq!
          end
        end
      end
    end
  end
end
