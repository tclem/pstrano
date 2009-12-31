# you can add more environments by creating their files in the deploy directory
# and including them here.
environment 'production' -default	# this tells pstrano to look for a file here: '.\deploy\production.ps1'
environment 'test' 

set application 'sample_application'
set scm git
set repository 'git://github.com'
set deploy_to '\Inetpub\wwwroot\$application'

# The next two line are identical ways of doing the same thing
#set main_server 'setup from deploy.ps1'
$main_server = 'setup from deploy.ps1'

#task Deploy {
#	"I'm in a custom deploy"
#}

task ExtraWork{
	# do something
} 	-description 'Describe what this task does'

task ExtraExtraWork{
}
task PreWork{
	"yeah buddy: $main_server"
}	-description 'Example of a before task'

after Deploy -do ExtraWork
after ExtraWork -do ExtraExtraWork
before Deploy -do PreWork

