# you can add more environments by creating their files in the deploy directory
# and including them here.
environment 'production' -default	# this tells pstrano to look for a file here: '.\deploy\production.ps1'
environment 'test' 

set application 'sample_application'
set deploy_to "\Inetpub\wwwroot\$application"

# First deployment strategy is using git and a remote_cache of the repository -> this is the fastest
#set deploy_via 'remote_cache'
set repository 'git://github.com/tclem/pstrano.git'

# Second deployment strategy is using http file download (expects a zip file) -> slower, but no dependencies
set deploy_via 'http'
set http_source 'http://github.com/tclem/pstrano/zipball/master'

task SomethingCool{

	Run {
	WriteHostName
	"This is my task running"}

} -description "Nice task"

after Setup -do SomethingCool

# Just examples of how to use before/after
#task ExtraWork {
#	# do something
#} 	-description 'Describe what this task does'
#
#task ExtraExtraWork{
#}
#task PreWork {
#	"yeah buddy, do some prework!"
#}	-description 'Example of a before task'
#
#after Deploy -do ExtraWork
#after ExtraWork -do ExtraExtraWork
#before Deploy -do PreWork

