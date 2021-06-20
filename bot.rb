require 'socket'
require 'json'

TWITCH_HOST = "irc.twitch.tv"
TWITCH_PORT = 6667

class TimerBot
  def initialize
    @is_running = false
    @current_time = nil
    @white_listed_commands = ['get']
  end

  def stop
    @is_running = false
    "Timer stopped! Time: #{parse_current_time}"
  end

  def get
    "Current time: #{parse_current_time}"
  end

  def interval
   while @is_running
      yield if block_given?
      sleep 1
    end
  end
 
  def parse_current_time
    if @current_time[:hours] == 0
      
      if @current_time[:minutes] == 0
        return "#{@current_time[:seconds]}s"
      end

      return "#{@current_time[:minutes]}m #{@current_time[:seconds]}s"
    end

    "#{@current_time[:hours]}h #{@current_time[:minutes]}m #{@current_time[:seconds]}s"
  end 

  def start
    @is_running = true
    @current_time = { hours: 0, minutes: 0, seconds: 0 }
    timer = Thread.new do 
      interval do
        @current_time[:seconds] += 1

        if @current_time[:seconds] == 60
          @current_time[:seconds] = 0
          @current_time[:minutes] += 1
        end

        if @current_time[:minutes] == 60
          @current_time[:minutes] = 0
          @current_time[:hours] += 1
        end
      end
    end

    timer.kill unless @is_running
    "Timer started!"
  end

  def check_user user
    allowed_users = get_allowed_users
    allowed_users.include? user 
  end

  def get_message_without_prefix message
    message.delete_prefix('!timer').delete(' ')
  end

  def get_allowed_users
    config_file_ptr = File.open('config.json')
    parsed_file_content = JSON.parse(config_file_ptr.read)
    parsed_file_content["allowed_users"]
  end

  def is_white_listed_command? command
    @white_listed_commands.include? command
  end
  
  def handle message_data
    command = get_message_without_prefix message_data[:content]

    white_listed_commands = ['get']
    if not check_user message_data[:username] and not is_white_listed_command? command 
      raise "Invalid User!"
    end

    begin
      return self.public_send command
    rescue NoMethodError => e
      return 'Invalid Command!'
    end
  end
end

class Bot
  def initialize
    bot_config = get_config_data

    @nickname  = "TimerBot"
    @password  = bot_config["password"]
    @channel   = bot_config["channel"]
    @socket    = TCPSocket.open TWITCH_HOST, TWITCH_PORT
    @timer_bot = TimerBot.new 

    start_communication
  end

  def get_config_data
    config_file_ptr = File.open('config.json')
    JSON.parse(config_file_ptr.read)
  end

  def write_to_socket message
    @socket.puts message
  end

  def write_to_chat message
    write_to_socket "PRIVMSG ##{@channel} :#{message}"
  end

  def start_communication
    write_to_socket "PASS #{@password}"
    write_to_socket "NICK #{@nickname}"
    write_to_socket "USER #{@nickname} 0 * #{@nickname}"
    write_to_socket "JOIN ##{@channel}"
  end

  def get_message_sender unparsed_message
    unparsed_message.match(/@(.*).tmi.twitch.tv/)[1]
  end

  def handle_message(message_data)
    if message_data[:content].start_with? '!timer'
      @timer_bot.handle message_data
    end
  end

  def run
    until @socket.eof? do
      message = @socket.gets.chomp
    
      if message.match(/PRIVMSG ##{@channel} :(.*)$/)
        content = $~[1]
        username = get_message_sender message

        write_to_chat handle_message({ content: content, username: username  })
      end
    end
  end
end

