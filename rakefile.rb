COMPILE_TARGET = ENV['config'].nil? ? "debug" : ENV['config']
require File.dirname(__FILE__) + "/build_support/BuildUtils.rb"

include FileTest
require 'albacore'
load "VERSION.txt"

RESULTS_DIR = "results"
PRODUCT = "FubuFastPack"
COPYRIGHT = 'Copyright 2008-2011 Chad Myers, Jeremy D. Miller, Joshua Flanagan, et al. All rights reserved.';
COMMON_ASSEMBLY_INFO = 'src/CommonAssemblyInfo.cs';
CLR_TOOLS_VERSION = "v4.0.30319"

tc_build_number = ENV["BUILD_NUMBER"]
build_revision = tc_build_number || Time.new.strftime('5%H%M')
build_number = "#{BUILD_VERSION}.#{build_revision}"

props = { :stage => File.expand_path("build"), :artifacts => File.expand_path("artifacts") }

desc "**Default**, compiles and runs tests"
task :default => [:compile, :unit_test]

desc "Target used for the CI server"
task :ci => [:default,:package,:nuget]

desc "Update the version information for the build"
assemblyinfo :version do |asm|
  asm_version = BUILD_VERSION + ".0"
  
  begin
    commit = `git log -1 --pretty=format:%H`
  rescue
    commit = "git unavailable"
  end
  puts "##teamcity[buildNumber '#{build_number}']" unless tc_build_number.nil?
  puts "Version: #{build_number}" if tc_build_number.nil?
  asm.trademark = commit
  asm.product_name = PRODUCT
  asm.description = build_number
  asm.version = asm_version
  asm.file_version = build_number
  asm.custom_attributes :AssemblyInformationalVersion => asm_version
  asm.copyright = COPYRIGHT
  asm.output_file = COMMON_ASSEMBLY_INFO
end

desc "Prepares the working directory for a new build"
task :clean do
	#TODO: do any other tasks required to clean/prepare the working directory
	FileUtils.rm_rf props[:stage]
    # work around nasty latency issue where folder still exists for a short while after it is removed
    waitfor { !exists?(props[:stage]) }
	Dir.mkdir props[:stage]
    
	Dir.mkdir props[:artifacts] unless exists?(props[:artifacts])
end

def waitfor(&block)
  checks = 0
  until block.call || checks >10 
    sleep 0.5
    checks += 1
  end
  raise 'waitfor timeout expired' if checks > 10
end


desc "Compiles the app"
task :compile => [:clean, :version, :bundle_fast_pack] do
  MSBuildRunner.compile :compilemode => COMPILE_TARGET, :solutionfile => 'src/FubuFastPack.sln', :clrversion => CLR_TOOLS_VERSION

  copyOutputFiles "src/FubuFastPack/bin/#{COMPILE_TARGET}", "FubuFastPack.{dll,pdb}", props[:stage]
end

desc "Bundles up the packaged content in FubuFastPack"
task :bundle_fast_pack do
  sh "lib/fubu/fubu.exe assembly-pak src/FubuFastPack -projfile FubuFastPack.csproj"
end


def copyOutputFiles(fromDir, filePattern, outDir)
  Dir.glob(File.join(fromDir, filePattern)){|file| 		
	copy(file, outDir) if File.file?(file)
  } 
end

desc "Runs unit tests"
task :test => [:unit_test]

desc "Runs unit tests"
task :unit_test => :compile do
  runner = NUnitRunner.new :compilemode => COMPILE_TARGET, :source => 'src', :platform => 'x86'
  runner.executeTests ['FubuFastPack.Testing']
end


desc "Runs the StoryTeller suite of end to end tests.  IIS must be running first"
task :storyteller => [:compile] do
  sh "lib/storyteller/StoryTellerRunner Storyteller.xml output/st-results.htm"
end


desc "Build the nuget package"
task :nuget do
	sh "lib/nuget.exe pack packaging/nuget/fubumvc.nuspec -o #{props[:artifacts]} -Version #{build_number}"
	sh "lib/nuget.exe pack packaging/nuget/fubumvc.fastpack.nuspec -o #{props[:artifacts]} -Version #{build_number}"
end