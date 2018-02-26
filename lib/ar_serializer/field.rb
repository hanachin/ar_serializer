class ArSerializer::Field
  attr_reader :includes, :preloaders, :data_block
  def initialize includes: nil, preloaders: [], data_block:
    @includes = includes
    @preloaders = preloaders
    @data_block = data_block
  end

  def self.count_field(klass, name, association_name)
    preloader = lambda do |models|
      klass.joins(association_name).where(id: models.map(&:id)).group(:id).count
    end
    data_block = lambda do |preloaded, _context, _params|
      preloaded[id] || 0
    end
    new preloaders: [preloader], data_block: data_block
  end

  def self.top_n_loader_available?
    return @top_n_loader_available unless @top_n_loader_available.nil?
    @top_n_loader_available = begin
      require 'top_n_loader'
      true
    rescue LoadError
      nil
    end
  end

  def self.create(klass, name, count_of:, includes:, preload:, &data_block)
    if count_of
      raise if includes || preload || data_block
      count_field klass, name, count_of
    elsif klass.reflect_on_association(name) && !includes && !preload && !data_block
      association_field klass, name
    else
      custom_field klass, name, includes: includes, preload: preload, &data_block
    end
  end

  def self.custom_field(klass, name, includes:, preload:, &data_block)
    if preload
      preloaders = Array(preload).map do |preloader|
        next preloader if preloader.is_a? Proc
        raise "preloader not found: #{preloader}" unless klass._custom_preloaders.has_key?(preloader)
        klass._custom_preloaders[preloader]
      end
    end
    preloaders ||= []
    includes ||= name if klass.reflect_on_association name
    raise if !preloaders.empty? && !data_block
    new(
      includes: includes,
      preloaders: preloaders,
      data_block: data_block || ->(_context, _params) { send name }
    )
  end

  def self.association_field(klass, name)
    preloader = lambda do |models, _context, params|
      if params
        limit = params[:limit]&.to_i
        order = params[:order]
      end
      return ActiveRecord::Associations::Preloader.new.preload models, name if !limit && !order
      return TopNLoader.load_associations klass, name, limit: params[:limit], order: params[:order] if limit && top_n_loader_available?
      order_key, order_mode = case order
      when nil
        [:id, :asc]
      when :asc
        [:id, :asc]
      when :desc
        [:id, :desc]
      when Hash
        key = keys.first
        mode = values.first.to_sym
        raise unless keys.size == 1
        raise unless klass.has_attribute? key
        raise unless [:asc, :desc].include? mode
        [keys.first.to_sym, mode]
      end
      limit = params[:limit].to_i if params[:limit]
      klass.where(id: models.map(&:id)).select(:id).joins(name).map do |r|
        records_nonnils, records_nils = r.send(name).partition(&order_key)
        records = records_nils + records_nonnils.sort_by(&order_key)
        records.reverse! if order_mode == :desc
        [r.id, limit ? records.take(limit) : records]
      end.to_h
    end
    data_block = lambda do |preloaded, _context, params|
      if params && (params[:limit] || params[:order_by])
        preloaded[id] || []
      else
        send name
      end
    end
    new preloaders: [preloader], data_block: data_block
  end
end