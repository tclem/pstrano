include 'config\deploy.ps1'

# Declare all variables that we need to run our tasks with the AllScope option 
#	this makes them available to all child scripts for overriding
set application $null -Option AllScope
set main_server $null -Option AllScope

task Setup {
} -description "Sets things up"

task Check{
} -description "Checks server dependencies and such"

task Deploy {
	"running deployment on $main_server (using scm: $scm)"
	"Deploying to these roles:"
	$roles | Format-List @{Name="Role";Expression={$_.name}}, @{Name="Host(s)";Expression={$_.value}}
} -description "Deploys code"

task Update `
	-description "Copies the latest code and updates the symlink" `
{

}

task UpdateCode{
}

task FinializeUpdate{
}

task SymLink{
}

task Restart{
}

task Rollback{
}

# it would be nice if we could do something like this
#namespace Deploy {
#	task SubTask{
#	}
#}


