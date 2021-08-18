package FlowPlugin::TriggerProperty;
use strict;
use warnings;
use base qw/FlowPDF/;
use FlowPDF::Log;
use Data::Dumper;
use JSON;

# Feel free to use new libraries here, e.g. use File::Temp;

# Service function that is being used to set some metadata for a plugin.
sub pluginInfo {
    return {
        pluginName          => '@PLUGIN_KEY@',
        pluginVersion       => '@PLUGIN_VERSION@',
        configFields        => ['config'],
        configLocations     => ['ec_plugin_cfgs'],
        defaultConfigValues => {}
    };
}

# Auto-generated method for the connection check.
# Add your code into this method and it will be called when configuration is getting created.
# $self - reference to the plugin object
# $p - step parameters
# $sr - StepResult object
# Parameter: config
# Parameter: desc
# Parameter: endpoint
# Parameter: credential

sub checkConnection {
    my ($self, $p, $sr) = @_;

    my $context = $self->getContext();
    my $configValues = $context->getConfigValues()->asHashref();
    logInfo("Config values are: ", $configValues);

    eval {
        # Use $configValues to check connection, e.g. perform some ping request
        # my $client = Client->new($configValues); $client->ping();
        my $password = $configValues->{password};
        if ($password ne 'secret') {
            # die "Failed to test connection - dummy check connection error\n";
        }
        1;
    } or do {
        my $err = $@;
        # Use this property to surface the connection error details in the CD server UI
        $sr->setOutcomeProperty("/myJob/configError", $err);
        $sr->apply();
        die $err;
    };
}
## === check connection ends ===


# Auto-generated method for the procedure Polling/Polling
# Add your code into this method and it will be called when step runs
# $self - reference to the plugin object
# $p - step parameters

# $sr - StepResult object
sub polling {
    my ($self, $p, $sr) = @_;

    my $ec = ElectricCommander->new();
    my $triggers = $ec->findObjects('trigger', {filter => [
        {propertyName => 'pluginKey', operator => 'equals', operand1 => '@PLUGIN_KEY@'},
    ]});


    for my $trigger ($triggers->findnodes('//trigger')) {
        my $name = $trigger->findvalue('triggerName') . '';
        my $enabled = $trigger->findvalue('triggerEnabled'). '';
        my $projectName = $trigger->findvalue('projectName'). '';

        my $pipelineName = $trigger->findvalue('pipelineName') . '';
        my $procedureName = $trigger->findvalue('procedureName') . '';
        my $releaseName = $trigger->findvalue('releaseName') . '';
        my $catalogItemName = $trigger->findvalue('catalogItemName') . '';
        my $catalogName = $trigger->findvalue('catalogName') . '';
        my $applicationName = $trigger->findvalue('applicationName') . '';

        unless($enabled) {
            logInfo "Trigger $projectName:$name is not enabled";
            next;
        }

        my $params = {};
        for ($trigger->findnodes("pluginParameters/parameterDetail")) {
            my $n = $_->findvalue('parameterName') . '';
            my $v = $_->findvalue('parameterValue') . '';
            $params->{$n} = $v;
        }
        logInfo "Processing trigger $projectName:$name";
        logInfo Dumper($params);


        my $propName = $params->{propName};
        my $prop = eval {
            $ec->getProperty({projectName => $projectName, propertyName => $propName});
        };
        if ($@) {
            logWarning "Failed to get property $propName";
            logWarning $@;
            next;
        }

        my $value = $prop->findvalue("//value") . '';
        my $lastModified = $prop->findvalue("//modifyTime") . '';

        my $state = eval {
                from_json($ec->getPropertyValue({
                    projectName => $projectName,
                    triggerName => $name,
                    propertyName => 'ec_trigger_state/triggerState'
                }))
        };

        $state ||= {};

        my $run = 0;
        if ($state->{value} ne $value) {
            logInfo "Value changed from $state->{value} to $value, running the trigger";
            $run = 1;
        }

        if ($state->{lastModified} && $state->{lastModified} ne $lastModified && $params->{fireOnTouch}) {
            logInfo "The property modification date has been changed, running the trigger";
            $run = 1;
        }
        if ($run) {

            my @children = $trigger->getChildNodes;
            my %runtimes = ();
            my @allowed = qw/applicationName catalogItemName catalogName parsedWebhookData pipelineName procedureName projectName releaseName triggerName/;
            for (@children) {
                my $n = $_->getName();
                my $v = $_->string_value;
                $runtimes{$n} = $v if $n && $v && grep { $n eq $_ } @allowed;
            }


            $ec->runTrigger({
                projectName => $projectName,
                triggerName => $name,
                %runtimes,
            });
            $state->{value} = $value;
            $state->{lastModified} = $lastModified;

            $ec->setProperty({
                projectName => $projectName,
                triggerName => $name,
                propertyName => 'ec_trigger_state/triggerState',
                value => to_json($state),
            });
            logInfo "Saved trigger state";
        }
        else {
            logInfo "Nothing changed";
        }
    }

}
## === step ends ===
# Please do not remove the marker above, it is used to place new procedures into this file.


1;
