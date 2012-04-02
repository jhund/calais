module Calais
  class Client
    # base attributes of the call
    attr_accessor :content
    attr_accessor :license_id

    # processing directives
    attr_accessor :content_type, :output_format, :reltag_base_url, :calculate_relevance, :omit_outputting_original_text
    attr_accessor :store_rdf, :metadata_enables, :metadata_discards

    # user directives
    attr_accessor :allow_distribution, :allow_search, :external_id, :submitter

    attr_accessor :external_metadata

    attr_accessor :use_beta

    def initialize(options={}, &block)
      options.each {|k,v| send("#{k}=", v)}
      yield(self) if block_given?
    end

    def enlighten
      post_args = {
        "licenseID" => @license_id,
        "content" => Iconv.iconv('UTF-8//IGNORE', 'UTF-8',  "#{@content} ").first[0..-2],
        "paramsXML" => params_xml
      }

      do_request(post_args)
    end

    def params_xml
      check_params
      Nokogiri::XML::Builder.new do |xml|
        xml.params do
          # add namespaces, store the opencalais one for later reference
          ns = xml.doc.root.add_namespace_definition('c', 'http://s.opencalais.com/1/pred/')
          xml.doc.root.add_namespace_definition('rdf', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#')
          # assign the saved namespace to params node
          xml.doc.root.namespace = ns

          xml['c'].processingDirectives(
            :calculateRelevanceScore => ('false' if @calculate_relevance == false),
            :contentType => (AVAILABLE_CONTENT_TYPES[@content_type] if @content_type),
            :discardMetadata => (@metadata_discards.join(';') unless @metadata_discards.empty?),
            :docRDFaccessible => (@store_rdf if @store_rdf),
            :enableMetadataType => (@metadata_enables.join(',') unless @metadata_enables.empty?),
            :omitOutputtingOriginalText => ('true' if @omit_outputting_original_text),
            :outputFormat => (AVAILABLE_OUTPUT_FORMATS[@output_format] if @output_format),
            :reltagBaseURL => (@reltag_base_url.to_s if @reltag_base_url)
          )

          xml['c'].userDirectives(
            :allowDistribution => (@allow_distribution.to_s unless @allow_distribution.nil?),
            :allowSearch => (@allow_search.to_s unless @allow_search.nil?),
            :externalID => (@external_id.to_s if @external_id),
            :submitter => (@submitter.to_s if @submitter)
          )

          if @external_metadata
            xml['c'].externalMetadata = @external_metadata
          end
        end
      end.to_xml(:indent => 2)
    end

    def url
      @url ||= URI.parse(calais_endpoint)
    end

    private
      def check_params
        raise 'missing content' if @content.nil? || @content.empty?

        content_length = @content.length
        raise 'content is too small' if content_length < MIN_CONTENT_SIZE
        raise 'content is too large' if content_length > MAX_CONTENT_SIZE

        raise 'missing license id' if @license_id.nil? || @license_id.empty?

        raise 'unknown content type' unless AVAILABLE_CONTENT_TYPES.keys.include?(@content_type) if @content_type
        raise 'unknown output format' unless AVAILABLE_OUTPUT_FORMATS.keys.include?(@output_format) if @output_format

        %w[calculate_relevance store_rdf allow_distribution allow_search].each do |variable|
          value = self.send(variable)
          unless NilClass === value || TrueClass === value || FalseClass === value
            raise "expected a boolean value for #{variable} but got #{value}"
          end
        end

        @metadata_enables ||= []
        unknown_enables = Set.new(@metadata_enables) - KNOWN_ENABLES
        raise "unknown metadata enables: #{unknown_enables.to_a.inspect}" unless unknown_enables.empty?

        @metadata_discards ||= []
        unknown_discards = Set.new(@metadata_discards) - KNOWN_DISCARDS
        raise "unknown metadata discards: #{unknown_discards.to_a.inspect}" unless unknown_discards.empty?
      end

      def do_request(post_fields)
        @request ||= Net::HTTP::Post.new(url.path)
        @request.set_form_data(post_fields)
        Net::HTTP.new(url.host, url.port).start {|http| http.request(@request)}.body
      end

      def calais_endpoint
         @use_beta ? BETA_REST_ENDPOINT : REST_ENDPOINT
      end
  end
end
