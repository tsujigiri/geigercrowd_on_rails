class DataSource < ActiveRecord::Base
  has_many :locations
  has_many :instruments, :as => :origin
  serialize :options, Hash
  validates_uniqueness_of :short_name, case_sensitive: false
  
  def to_param
    short_name
  end

  # Runs the Scraper and fetches new samples
  def fetch
    return false if self.fetched_at and Time.now - self.fetched_at <= self.update_interval
    self.options[:urls].each do |url|
      Location.transaction do
        data = self.parser_class.constantize.new(url).parse
    
        data.each do |d|
          location = Location.where(:name => d.location_name, :data_source_id => self.id).first
          unless location
            # Assign a new location
            location = Location.new(:name => d.location_name, :data_source_id => self.id)
            location.save(:validate => false)
          end
          
          # Skip if no value was parsed
          next if d.value.nil?
          
          # Skip if we already have a sample for this location, instrument and time
          last_sample = Sample.where(:location_id => location.id).last
          next if last_sample and last_sample.timestamp == d.date_time
          
          # Create the sample
          sample = Sample.new(:value => d.value, :location_id => location.id, :timestamp => d.date_time)
          sample.instrument = last_sample.instrument if last_sample
          
          unless sample.instrument
            # Assign a new instrument
            sample.instrument = Instrument.new(:model => 'Autogenerated', :notes => "Autogenerated", :location_id => location.id)
            sample.instrument.origin = self
            sample.instrument.data_type = DataType.where(:name => d.value_type).first || DataType.create!(:name => d.value_type)
            sample.instrument.save(:validate => false)
          end
          

          sample.save(:validate => false)
        end
      end
    end
    self.fetched_at = Time.now
    self.save!

    return true    

  end
  
end
