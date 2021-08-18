# On upgrade promote is ran first, so if we have a schedule and it is already disabled,
# we will not enable it again
my $schedProject = 'Electric Cloud';
my $schedName = 'PropertyPollingTrigger';
my $schedulePath = "/projects/${schedProject}/schedules/${schedName}";
my $disabledByDemotePath = "${schedulePath}/ec_disabledByDemote";
my $newApisSupported = undef;

if ($promoteAction eq 'promote') {
    # Clean install or upgrade to 1.1.0 version
    if (!scheduleExists($schedProject, $schedName)) {
        if (!projectExists($schedProject)) {
            $batch->createProject($schedProject, {description => "Electric Cloud Procedures"});
        }

        $batch->createSchedule($schedProject, $schedName, {
            description      => 'System schedule to check Git repository polling triggers.',
            scheduleDisabled => 'false',
            procedureName    => '/plugins/@PLUGIN_KEY@/project/procedures/Polling',
            intervalUnits    => 'minutes',
            interval         => 5
        });
    }
    else {
        # If schedule is disabled by the system, we should enable it back
        # We are using this to check if schedule is present
        my $isDisabled = getProp("$schedulePath/scheduleDisabled");
        if ($isDisabled eq 'true') {
            my $disabledByDemote = getBooleanPropertySafe($disabledByDemotePath);
            if ($disabledByDemote == 1) {
                $batch->modifySchedule($schedProject, $schedName, {
                    scheduleDisabled => 'false'
                });

                # Cleaning the flag
                $batch->deleteProperty($disabledByDemotePath);
            }
        }
    }
}
elsif ($promoteAction eq 'demote' && scheduleExists($schedProject, $schedName)) {
    my $isDisabled = getProp("$schedulePath/scheduleDisabled");

    if ($isDisabled eq 'false') {
        # Disabling schedule and adding a property
        # to specify that it is disabled by the system
        $batch->modifySchedule($schedProject, $schedName, {
            scheduleDisabled => 'true'
        });

        $batch->createProperty('ec_disabledByDemote', {
            projectName  => $schedProject,
            scheduleName => $schedName,
            expandable   => 'false',
            propertyType => 'string',
            value        => 'true'
        });
    }
}

sub getProp {
    my ($path) = @_;

    my $value = undef;

    eval {
        my $prop = $commander->getProperty($path);
        $value = $prop->findvalue('//value')->string_value();
        1;
    };

    # Cleaning the error buffer
    $commander->getError() unless defined $value;

    return $value;
}

sub scheduleExists {
    my ($project, $name) = @_;
    my $exists = 0;
    eval {
        my $sched = $commander->getSchedule($project, $name);
        $exists = $name eq $sched->findvalue('//scheduleName')->string_value();
    };
    return $exists;
}

sub projectExists {
    my ($project) = @_;
    my $exists = 0;
    eval {
        my $proj = $commander->getProject($project);
        if ($proj) {
            $exists = $project eq $proj->findvalue('//projectName')->string_value();
        }
    };
    return $exists;
}

sub getBooleanPropertySafe {
    my ($propertyPath) = @_;

    my $disabledByDemote = 0;

    eval {
        my $disabled = $commander->getProperty($propertyPath);
        if ($disabled->findvalue("//value")->string_value()) {
            $disabledByDemote = 1;
        };
        1;
    } or do {
        # Clearing errors
        $commander->{errorMsg} = '';
    };

    return $disabledByDemote;
}
