#
# Author:: Adam Edwards (<adamed@getchef.com>)
#
# Copyright:: 2014, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/util/powershell/cmdlet'
require 'chef/util/dsc/lcm_output_parser'

class Chef::Util::DSC
  class LocalConfigurationManager
    def initialize(node, configuration_path)
      @node = node
      @configuration_path = configuration_path
      clear_execution_time
    end

    LCM_MODULE_NOT_INSTALLED_ERROR_CODE = 0x80131500

    def test_configuration(configuration_document)
      status = run_configuration_cmdlet(configuration_document)
      command_output = status.return_value
      unless status.succeeded?
        if status.status.exitstatus == LCM_MODULE_NOT_INSTALLED_ERROR_CODE
          Chef::Log::warn('Unable to test configuration because a required DSC PowerShell module may not be installed.')
          command_output = ''
        end
        if status.stderr.gsub(/\s+/, ' ') =~ /A parameter cannot be found that matches parameter name 'Whatif'/
          # LCM returns an error if any of the resources do not support the opptional What-If
          Chef::Log::warn("Received error while testing configuration due to resource not supporting 'WhatIf'")
        else
          raise Chef::Exceptions::PowershellCmdletException, "Powershell Cmdlet failed: #{status.stderr.gsub(/\s+/, ' ')}"
        end
      end
      configuration_update_required?(command_output)
    end

    def set_configuration(configuration_document)
      run_configuration_cmdlet(configuration_document, true)
    end

    def last_operation_execution_time_seconds
      if @operation_start_time && @operation_end_time
        @operation_end_time - @operation_start_time
      end
    end

    private

    def run_configuration_cmdlet(configuration_document, apply_configuration = false)
      Chef::Log.debug("DSC: Calling DSC Local Config Manager to #{apply_configuration ? "set" : "test"} configuration document.")
      test_only_parameters = ! apply_configuration ? '-whatif; if (! $?) { exit 1 }' : ''

      start_operation_timing
      command_code = lcm_command_code(@configuration_path, test_only_parameters)
      status = nil

      begin
        save_configuration_document(configuration_document)
        cmdlet = ::Chef::Util::Powershell::Cmdlet.new(@node, "#{command_code}")
        if apply_configuration
          status = cmdlet.run!
        else
          status = cmdlet.run
        end
      ensure
        end_operation_timing
        remove_configuration_document
        if last_operation_execution_time_seconds
          Chef::Log.debug("DSC: DSC operation completed in #{last_operation_execution_time_seconds} seconds.")
        end
      end
      Chef::Log.debug("DSC: Completed call to DSC Local Config Manager")
      status
    end

    def lcm_command_code(configuration_path, test_only_parameters)
      <<-EOH
try
{
  $ProgressPreference = 'SilentlyContinue';start-dscconfiguration -path #{@configuration_path} -wait -force #{test_only_parameters} -erroraction 'Stop'
}
catch [Microsoft.Management.Infrastructure.CimException]
{
  $exception = $_.Exception
  write-error -Exception $exception
  $StatusCode = 1
  if ( $exception.HResult -ne 0 )
  {
    $StatusCode = $exception.HResult
  }
  $exception | format-table -property * -force
  exit $StatusCode
}
EOH
    end

    def configuration_update_required?(what_if_output)
      Chef::Log.debug("DSC: DSC returned the following '-whatif' output from test operation:\n#{what_if_output}")
      begin
        Parser::parse(what_if_output)
      rescue Chef::Util::DSC::LocalConfigurationManager::Parser => e
        Chef::Log::warn("Could not parse LCM output: #{e}")
        [Chef::Util::DSC::ResourceInfo.new('Unknown DSC Resources', true, ['Unknown changes because LCM output was not parsable.'])]
      end
    end

    def save_configuration_document(configuration_document)
      ::FileUtils.mkdir_p(@configuration_path)
      ::File.open(configuration_document_path, 'wb') do | file |
        file.write(configuration_document)
      end
    end

    def remove_configuration_document
      ::FileUtils.rm(configuration_document_path)
    end

    def configuration_document_path
      File.join(@configuration_path,'..mof')
    end

    def clear_execution_time
      @operation_start_time = nil
      @operation_end_time = nil
    end

    def start_operation_timing
      clear_execution_time
      @operation_start_time = Time.now
    end

    def end_operation_timing
      @operation_end_time = Time.now
    end
  end
end
