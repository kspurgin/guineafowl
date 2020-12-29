require 'csv'
require 'pp'

require 'pry'

MALES = 3
FEMALES = 4
NO_MATES = false
RECENT_HISTORY = 'recent_history.txt'
HISTORY_CT = 2
FULL_HISTORY = 'full_history.txt'

class NoBirdByThatNameError < StandardError; end
class NotEnoughBirdsError < StandardError; end

class Guinea
  attr_reader :name, :cohort, :sex, :mates

  def initialize(name:, cohort:, sex:)
    @name = name
    @cohort = cohort.to_i
    @sex = sex
    @mates = []
  end
end

class Rasp
  attr_reader :guineas

  def initialize
    @guineas = []
    create_birds
    assign_mates
  end

  def females
    @guineas.select{ |bird| bird.sex == 'f' }.sort_by{ |bird| bird.cohort }
  end

  def grab(name)
    bird = @guineas.find{ |guinea| guinea.name == name }
    raise NoBirdByThatNameError, name if bird.nil?
    bird
  end
  
  def males
    @guineas.select{ |bird| bird.sex == 'm' }.sort_by{ |bird| bird.cohort }
  end

  def mates_of(name)
    @guineas.select{ |bird| bird.mates.include?(name) }
  end

  def select
    puts Selector.new(rasp: self)
  end
  
  private

  def create_birds
    CSV.foreach('birds.csv', headers: true) do |bird|
      @guineas << Guinea.new(name: bird['name'],
                             cohort: bird['cohort'],
                             sex: bird['sex']
                            )
    end
  end

  def assign_mates
    mate_data.each do |name, mates|
      bird = grab(name)
      mates.each{ |mate| bird.mates << mate }
    end
  end

  def mate_data
    h = {}
    CSV.foreach('relationships.csv', headers: true) do |row|
      male = row['male']
      female = row['female']
      [male, female].each{ |sex| h[sex] = [] unless h.key?(sex) }
      h[male] << female
      h[female] << male
    end
    h
  end
end

class Selector
  def initialize(rasp:)
    @rasp = rasp
    @males = rasp.males
    @females = rasp.females
    @selection = []
    @recent_history = read_recent_history
    make_selection
    write_history
    puts ""
  end

  def names
    @selection.map{ |bird| bird.name }.sort
  end

  private

  def selected_ct_by_sex(sex)
    @selection.select{ |bird| bird.sex == sex }
  end

  def enough_of_sex?(sex)
    ct = sex == 'm' ? MALES : FEMALES
    selected_ct_by_sex(sex).size == ct ? true : false
  end

  def make_selection
    %w[f m].each do |sex|
      set = sex == 'm' ? @males : @females
      backup = []
      last_resort = []
      until enough_of_sex?(sex)
        if set.empty?
          if backup.empty?
            candidate = last_resort.sample
            last_resort.delete(candidate)
          else
            candidate = backup.sample
            backup.delete(candidate)
          end
        else
          candidate = set.sample
          set.delete(candidate)
          
          if NO_MATES && mates_of_selected.include?(candidate.name)
            candidate = nil
          else
            unless @recent_history.empty?
              if @recent_history.size == 1
                candidate = nil if @recent_history.first.any?(candidate.name)
              else
                if @recent_history.first.any?(candidate.name)
                  backup << candidate
                  candidate = nil
                elsif @recent_history.last.any?(candidate.name)
                  last_resort << candidate
                  candidate = nil
                end
              end
            end
          end
        end
        @selection << candidate unless candidate.nil?
        puts "Selected #{candidate.name}" unless candidate.nil?
      end
    end
  end

  def mates_of_selected
    mates = []
    @selection.each{ |bird| mates << bird.mates }
    mates.flatten.uniq
  end

  def read_recent_history
    return [] unless File.file?(RECENT_HISTORY)

    history = []
    h = File.new(RECENT_HISTORY)
    h.each{ |ln| history << ln.chomp.split('|') }
    history
  end
  
  def select_sex(sex)
    all = sex == 'm' ? @rasp.males : @rasp.females
    all.sample
  end

  def write_history
    @recent_history.shift if @recent_history.size >= HISTORY_CT
    @recent_history << names
    File.open(RECENT_HISTORY, 'w') do |file|
      @recent_history.each{ |h| file.puts(h.join('|')) }
    end
    File.open(FULL_HISTORY, 'a') do |file|
      file.puts(names.join('|'))
    end
  end
end

class CsvPlot
  def initialize(path:)
    @path = path
    @headers = Rasp.new.guineas.map{ |bird| bird.name }.sort
    @headers.prepend('day')
    @data = get_full_history
    write_data
  end

  private

  def get_full_history
    history = []
    ct = 1
    File.readlines(FULL_HISTORY).each do |ln|
      h = { 'day' => ct }
      ct += 1
      ln.chomp.split('|').each{ |bird| h[bird] = '1' }
      @headers.each{ |hdr| h[hdr] = '0' unless h.key?(hdr) }
      history << h
    end
    history
  end

  def write_data
    CSV.open(@path, 'wb') do |csv|
      csv << @headers
      @data.each{ |h| csv << h.values_at(*@headers) }
    end
  end
end

File.delete(RECENT_HISTORY)
File.delete(FULL_HISTORY)
r = Rasp.new
31.times { r.select }
CsvPlot.new(path: 'mate_agnostic.csv')


NO_MATES = true
File.delete(RECENT_HISTORY)
File.delete(FULL_HISTORY)
r = Rasp.new
31.times { r.select }
CsvPlot.new(path: 'no_mates.csv')
