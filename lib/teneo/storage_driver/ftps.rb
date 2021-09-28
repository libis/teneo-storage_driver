# frozen_string_literal: true

require_relative 'base'

require 'net/ftp'
require 'tempfile'

module Teneo
  module StorageDriver
    
    class Ftps < Base
      protocol 'FTPS'
      description 'FTPS server'
      local? false

      class Dir < Base::Dir
        def driver_path
          @path
        end
      end

      class File < Base::File
        class Cleaner
          def initialize(tmpfile)
            @pid = Process.pid
            @tmpfile = tmpfile
          end

          def call(*_args)
            return if @pid != Process.pid
            ::File.delete(@tmpfile)
          rescue Errno::ENOENT
            # ignore
          end
        end

        def initialize(path:, driver:)
          work_path = ::File.join(driver.work_dir, path)
          ObjectSpace.define_finalizer(self, Cleaner.new(work_path))
          super path: work_path, driver: driver
          @remote_path = path
        end

        # @return [String (frozen)]
        def driver_path
          @remote_path
        end

        # @param [TrueClass, FalseClass] force
        # @return [TrueClass]
        def localize(force = false)
          return nil if @localized && !force
          #noinspection RubyResolve
          raise Errno::ENOENT unless exist?
          FileUtils.mkpath(::File.dirname(@path))
          @driver.download(remote: @remote_path, local: @path)
          @localized = true
        end

        def save_remote
          @driver.mkpath(::File.dirname(@remote_path))
          @driver.upload(local: @path, remote: @remote_path)
        end

        # @param [String] new_name
        # @return [String] new driver path
        def rename(new_name)
          @remote_path = do_rename(new_name)
        end

        # @param [String] new_dir
        # @return [String] new driver path
        def move(new_dir)
          @remote_path = do_move(new_dir)
        end

        protected

        attr_reader :remote_path
      end

      # Create FTPS driver
      # @param [String] host name or ip adress of the server
      # @param [Integer] port (21) number of the port the server is listening on
      # @param [String] user login name
      # @param [String] password login password
      # @param [String] location remote root path
      # @param [Boolean] binary (true) default transfer mode
      def initialize(host:, port: 21, user:, password:, location:, binary: true)
        @host = host
        @port = port
        @user = user
        @password = password
        @root = location
        @binary = binary
        connect
      end

      # A unique name for this storage driver instance
      # @return [String (frozen)]
      def name
        "#{self.class.name.split('::').last}-#{Zlib::crc32("#{@host}#{@root}").to_s(36)}"
      end

      # The working dir where local copies of remote files are stored
      # @param [String] value new path, not changed if nil or omitted
      # @return [String] the workdir
      def work_dir(value = nil)
        @workdir = value unless value.nil?
        @workdir || ::File.join(::Dir.tmpdir, name)
      end

      # @param [String] path
      # @return [String]
      def entry_path(path)
        safepath(path)
      end

      # Create a directory
      # @param [String] path
      # @return [Teneo::StorageDriver::Ftps::Dir, FalseClass]
      def mkdir(path)
        unless dir_exist?(path)
          ftp_service do |conn|
            conn.mkdir(abspath(path))
          end
        end
        super
      end

      # Create a directory tree
      # @param [String] path
      # @return [Teneo::StorageDriver::Ftps::Dir, FalseClass]
      def mkpath(path)
        unless dir_exist?(path)
          unless ::File::SEPARATOR == path
            parent_dir = ::File.dirname(path)
            mkpath(parent_dir)
          end
          ftp_service do |conn|
            conn.mkdir(abspath(path))
          end
        end
        super
      end

      # Test if directory exists
      # @param [String] path
      # @return [TrueClass, FalseClass]
      def dir_exist?(path)
        ftp_service do |conn|
          conn.chdir(abspath(path))
          conn.chdir('/')
          true
        end
      rescue ::Net::FTPError
        return false
      end

      # Test if file exists
      # @param [String] path
      # @return [TrueClass, FalseClass]
      def file_exist?(path)
        is_file?(path)
      end

      # Test if file or directory exists
      # @param [String] path
      # @return [TrueClass, FalseClass]
      def exist?(path)
        file_exist?(path) || dir_exist?(path)
      end

      # Check if remote path is a file (or a directory)
      # @param [String] path
      # @return [TrueClass, FalseClass] true if file, false otherwise
      def is_file?(path)
        ftp_service do |conn|
          conn.size(abspath(path)).is_a?(Numeric) ? true : false
        end
      rescue ::Net::FTPError
        false
      end

      # Download a file
      # @param [String] remote remote file path
      # @param [String] local local file path
      # @return [FalseClass, TrueClass]
      def download(remote:, local:)
        ftp_service do |conn|
          conn.getbinaryfile(abspath(remote), local)
        end
        true
      rescue ::Net::FTPError
        false
      end

      # Upload a file
      # @param [String] local local file path
      # @param [String] remote remote file path
      # @return [FalseClass, TrueClass]
      def upload(local:, remote:)
        ftp_service do |conn|
          conn.putbinaryfile(local, abspath(remote))
        end
        true
      rescue ::Net::FTPError
        false
      end

      # Delete a file
      # @param [String] path remote file or directory path
      # @return [FalseClass, TrueClass]
      def delete(path)
        ftp_service do |conn|
          is_file?(path) ? conn.delete(abspath(path)) : conn.rmdir(abspath(path))
        end
        true
      rescue ::Net::FTPError
        false
      end

      # Delete a directory
      # @param [String] path remote directory
      # @return [FalseClass, TrueClass]
      def del_tree(path)
        entries(path).map { |e| del_tree(e) } unless is_file?(path)
        delete(path)
      end

      # get last modification time
      # @param [String] path
      # @return [Time] file modification time
      def mtime(path)
        ftp_service do |conn|
          conn.mtime(abspath(path))
        end
      rescue ::Net::FTPError
        nil
      end

      # rename a file or folder
      # @param [String] from_path
      # @param [String] to_path
      # @return [String] new name
      def rename(from_path, to_path)
        ftp_service do |conn|
          conn.rename(abspath(from_path), abspath(to_path))
        end
        entry_path(to_path)
      rescue ::Net::FTPError
        nil
      end

      # get file size
      # @param [String] path
      # @return [Integer] file size
      def size(path)
        ftp_service do |conn|
          conn.size(abspath(path))
        end
      rescue ::Net::FTPError
        0
      end

      protected

      # @param [String] path
      # @param [Proc] block
      # @return [Array<String>]
      def dir_children(path, &block)
        ftp_service do |conn|
          conn.nlst(abspath(path)).map do |e|
            block.call relpath(e)
          end
        end
      end

      # @return [Net::FTP]
      # def ftp_service
      #   @connection
      # end

      # Tries to execute ftp commands; reconnects and tries again if connection timed out
      def ftp_service
        yield @connection
      rescue Errno::ETIMEDOUT, Net::FTPConnectionError, Errno::EPIPE
        disconnect
        connect
        yield @connection
      end

      # Connect to FTP server
      # @return [Net::FTP]
      def connect
        connection_params = {
          port: @port,
          ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
          passive: true,
          username: @user,
          password: @password,
          open_timeout: 10.0,
        }
        @connection = Net::FTP.new(@host, connection_params)
      end

      # Disconnect from FTP server
      def disconnect
        ftp_service do |conn|
          conn.close
        end
      rescue ::Net::FTPError
        # do nothing
      end
    end

  end
end
