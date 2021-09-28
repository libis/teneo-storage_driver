# frozen_string_literal: true

require 'pathname'
require 'fileutils'
require 'zlib'

module Teneo
  module StorageDriver

    class Base

      # @return [Array<Teneo::StorageDriver::Base>]
      def self.drivers
        @drivers ||= ObjectSpace.each_object(Class).select { |klass| klass < self }
      end

      # @return [Array<String>]
      def self.protocols
        drivers.map { |klass| klass.protocol }
      end

      # @param [String] protocol
      # @return [Teneo::StorageDriver::Base]
      def self.driver(protocol)
        drivers.find { |d| d.protocol == protocol }
      end

      # @param [String] value
      # @return [String]
      def self.protocol(value = nil)
        @protocol = value unless value.nil?
        @protocol
      end

      # @param [String] value
      # @return [String]
      def self.description(value = nil)
        @description = value unless value.nil?
        @description || ''
      end

      # @param [TrueClass, FalseClass] value
      # @return [TrueClass, FalseClass]
      def self.local?(value = nil)
        @local = value unless value.nil?
        @local
      end

      class Entry

        # @param [String] path
        # @param [Teneo::StorageDriver::Base] driver
        def initialize(path:, driver:)
          @path = path
          @driver = driver
        end

        # @return [Teneo::StorageDriver::Base]
        def driver
          @driver
        end

        # @return [String]
        def driver_path
          @driver.relpath(@path)
        end

        # @return [String]
        def local_path
          @path
        end

        # @return [TrueClass, FalseClass]
        def exist?
          @driver.exist?(driver_path)
        end

        # @return [TrueClass, FalseClass]
        def local?
          @driver.class.local?
        end

        # @return [String]
        def protocol
          @driver.class.protocol
        end

        # @return [TrueClass, FalseClass]
        def delete
          @driver.delete(driver_path)
        end

        # @return [DateTime]
        def mtime
          @driver.mtime(driver_path)
        end

        # @return [Integer]
        def size
          @driver.size(driver_path)
        end

        # @param [String] new_name
        # @return [String]
        def rename(new_name)
          @path = do_rename(new_name)
        end

        # @param [String] new_name
        # @return [String]
        def do_rename(new_name)
          new_path = ::File.join(::File.dirname(driver_path), ::File.basename(new_name))
          @driver.rename(driver_path, new_path)
        end

        protected :do_rename

        # @param [String] new_dir
        # @return [String]
        def move(new_dir)
          @path = do_move(new_dir)
        end

        # @param [String] new_dir
        # @return [String]
        def do_move(new_dir)
          new_path = ::File.join(new_dir, ::File.basename(driver_path))
          new_path = ::File.join(::File.dirname(driver_path), new_path) unless Pathname.new(new_dir).absolute?
          @driver.dir(::File.dirname(new_path)).touch
          @driver.rename(driver_path, new_path)
        end

        protected :do_move
      end

      class Dir < Teneo::StorageDriver::Base::Entry

        # @return [FalseClass]
        def file?
          false
        end

        # @return [TrueClass, FalseClass]
        def exist?
          @driver.dir_exist?(driver_path)
        end

        # @param [Proc] block
        # @return [Array<String>]
        def entries(&block)
          @driver.entries(driver_path, &block)
        end

        # @param [Proc] block
        # @return [Array<Teneo::StorageDriver::Base::File, Teneo::StorageDriver::Base::Dir>]
        def obj_entries(&block)
          @driver.obj_entries(driver_path, &block)
        end

        # @param [String (frozen)] path
        # @return [Teneo::StorageDriver::Base::Dir]
        def dir(path = '..')
          return self if is_root?
          path = ::File.join(driver_path, path)
          @driver.dir(path)
        end

        # @param [String] path
        # @return [Teneo::StorageDriver::Base::File]
        def file(path)
          @driver.file(::File.join(driver_path, path))
        end

        def touch
          dir.touch unless is_root?
          @driver.mkdir(driver_path) unless exist?
        end

        # @return [TrueClass, FalseClass]
        def is_root?
          ::File::SEPARATOR == driver_path
        end
      end

      class File < Teneo::StorageDriver::Base::Entry
        def initialize(path:, driver:)
          super
          @localized = false
        end

        # @return [TrueClass]
        def file?
          true
        end

        # @return [TrueClass, FalseClass]
        def exist?
          @driver.file_exist?(driver_path)
        end

        # @param [TrueClass, FalseClass] force
        # @return [TrueClass]
        def localize(force = false)
          # do nothing
        end

        def save_remote
          # do nothing
        end

        # @return [Teneo::StorageDriver::Base::Dir]
        def dir
          @driver.dir(::File.dirname(driver_path))
        end

        # @return [Object]
        def touch
          return nil if exist?
          FileUtils.mkpath(::File.dirname(local_path))
          FileUtils.touch(local_path)
          save_remote
        end

        # @return [String, Object]
        def read
          localize
          return false unless exist?
          ::File.open(local_path, 'rb') do |f|
            block_given? ? yield(f) : f.read
          end
        end

        # @param [String] data
        def write(data = nil)
          FileUtils.mkpath(::File.dirname(local_path))
          ::File.open(local_path, 'wb') do |f|
            block_given? ? yield(f) : f.write(data)
          end
          save_remote
        end

        # @param [String] data
        def append(data = nil)
          localize
          FileUtils.mkpath(::File.dirname(local_path))
          ::File.open(local_path, 'ab') do |f|
            block_given? ? yield(f) : f.write(data)
          end
          save_remote
        end

        # @param [String, Teneo::StorageDriver::Base::File, Teneo::StorageDriver::Base::Dir] target
        # @return [String, Teneo::StorageDriver::Base::File, Teneo::StorageDriver::Base::Dir, FalseClass]
        def copy_to(target)
          case target
          when nil
            return false
          when String
            FileUtils.cp local_path, target
            return target
          when Teneo::Base::File
            FileUtils.cp local_path, target.local_path
          when Teneo::Base::Dir
            target = target.file(::File.basename(local_path))
            FileUtils.cp local_path, target.local_path
          else
            raise RuntimeError, "target class not supported: #{target.klass}"
          end
          target.save_remote
          target
        end

        # @param [String, Teneo::StorageDriver::Base::File, Teneo::StorageDriver::Base::Dir] target
        # @return [Teneo::StorageDriver::Base::File, FalseClass] self if success, false otherwise
        def copy_from(target)
          case target
          when nil
            return false
          when String
            FileUtils.cp target, local_path
          when Teneo::Base::File
            FileUtils.cp target.local_path, local_path
          when Teneo::Base::Dir
            target = target.file(File.basename(local_path))
            FileUtils.cp target.local_path, local_path
          else
            raise RuntimeError, "target class not supported: #{target.klass}"
          end
          save_remote
          self
        end
      end

      # @return [String (frozen)]
      def name
        "#{self.class.name.split('::').last}-#{Zlib::crc32(root).to_s(36)}"
      end

      # @return [String]
      def work_dir
        @root
      end

      def entry_path(path)
        safepath(path)
      end

      # Get directory listing
      # @param [String] path
      # @return [Array<String>]
      def entries(path = nil)
        path ||= ::File::SEPARATOR
        dir_children(path) do |e|
          if block_given?
            yield e
          else
            e
          end
        end.cleanup
      end

      # Get directory listing
      # @param [String] path
      # @return [Array<Teneo::StorageDriver::Base::File, Teneo::StorageDriver::Base::Dir>]
      def obj_entries(path = nil)
        path ||= ::File::SEPARATOR
        #noinspection RubyYardReturnMatch
        dir_children(path) do |e|
          e = entry(e)
          if block_given?
            yield e
          else
            e
          end
        end.cleanup
      end

      # Get a File or Dir object for a given path. Path should exist.
      # @param [String] path
      # @return [Teneo::StorageDriver::Base::File, Teneo::StorageDriver::Base::Dir]
      def entry(path)
        return nil unless self.exist?(path)
        #noinspection RubyYardReturnMatch
        (self.class.name + '::' + (self.is_file?(path) ? 'File' : 'Dir')).
          constantize.new(path: entry_path(path), driver: self)
      end

      # Get a File object for a given path. Path is not required to exist
      # @param [String] path
      # @return [Teneo::StorageDriver::Base::File]
      def file(path)
        return self.dir(path) if file_exist?(path) && !is_file?(path)
        #noinspection RubyYardReturnMatch
        (self.class.name + '::File').constantize.new(path: entry_path(path), driver: self)
      end

      # Get a Dir object for a given path. Path is not required to exist
      # @param [String] path
      # @return [Teneo::StorageDriver::Base::Dir]
      def dir(path = nil)
        path ||= ::File::SEPARATOR
        return self.file(path) if file_exist?(path) && is_file?(path)
        #noinspection RubyYardReturnMatch
        (self.class.name + '::Dir').constantize.new(path: entry_path(path), driver: self)
      end

      # @return [String]
      def root
        @root.freeze
      end

      # @param [String] path
      # @return [String]
      def abspath(path)
        ::File.join(@root, safepath(path))
      end

      # @param [String] path
      # @return [String]
      def relpath(path)
        p = ::File.join(::File::SEPARATOR, safepath(path))
        Pathname(p).relative_path_from(Pathname(@root)).to_s
      rescue ArgumentError
        ::File::SEPARATOR
      end

      # @param [String] path
      # @return [String]
      def safepath(path)
        ::File.expand_path(::File::SEPARATOR + path.gsub(/^#{Regexp.escape(::File::SEPARATOR)}+/, ''), ::File::SEPARATOR)
      end

      # Test if file or directory exists
      # @param [String] path
      # @return [TrueClass, FalseClass]
      def exist?(path)
        file_exist?(path) || dir_exist?(path)
      end

      # Need to be overwritten

      # @param [String] path
      # @return [Teneo::StorageDriver::Base::Dir,FalseClass]
      def mkdir(path)
        exist?(path) ? dir(path) : false
      end

      # @param [String] path
      # @return [Teneo::StorageDriver::Base::Dir,FalseClass]
      def mkpath(path)
        exist?(path) ? dir(path) : false
      end

      # @param [String] path
      # @return [TrueClass, FalseClass]
      def file_exist?(path)
        raise NotImplementedError, 'Method needs implementation'
      end

      # @param [String] path
      # @return [TrueClass, FalseClass]
      def dir_exist?(path)
        raise NotImplementedError, 'Method needs implementation'
      end

      # @param [String] path
      # @return [TrueClass, FalseClass]
      def is_file?(path)
        raise NotImplementedError, 'Method needs implementation'
      end

      # @param [String] path
      def delete(path)
        raise NotImplementedError, 'Method needs implementation'
      end

      # @param [String] path
      def del_tree(path)
        raise NotImplementedError, 'Method needs implementation'
      end

      # @param [String] path
      def mtime(path)
        raise NotImplementedError, 'Method needs implementation'
      end

      # @param [String] from_name
      # @param [String] to_name
      def rename(from_name, to_name)
        raise NotImplementedError, 'Method needs implementation'
      end

      # @param [String] path
      # @return [Integer]
      def size(path)
        raise NotImplementedError, 'Method needs implementation'
      end

      protected

      # @param [String] path
      # @param [Proc] block
      # @return [Array<String>]
      def dir_children(path, &block)
        raise NotImplementedError, 'Method needs implementation'
      end

      attr_accessor :path
    end
    
  end
end
