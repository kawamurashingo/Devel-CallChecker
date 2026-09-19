#!/usr/bin/env perl
use 5.010;
use strict;
use warnings;
use Config;
use Cwd qw(abs_path getcwd);
use File::Path qw(make_path remove_tree);
use File::Spec;
use Getopt::Long qw(GetOptions);
use JSON::PP qw(decode_json);
use POSIX qw(WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG);

my $inventory = File::Spec->catfile(qw(maint downstream inventory.json));
my $work = File::Spec->catdir(qw(maint downstream .work));
my $results = File::Spec->catdir(qw(maint downstream results));
my ($only, $help);
my $candidate = abs_path(".");

GetOptions(
    "inventory=s" => \$inventory,
    "work=s" => \$work,
    "results=s" => \$results,
    "only=s" => \$only,
    "candidate=s" => \$candidate,
    "help" => \$help,
) or usage();
usage() if $help;

# Resolve runner-owned paths before any candidate build chdir.  Otherwise
# relative log paths are interpreted from an external --candidate directory.
my $launch_dir = getcwd();
$inventory = File::Spec->rel2abs($inventory, $launch_dir);
$work      = File::Spec->rel2abs($work,      $launch_dir);
$results   = File::Spec->rel2abs($results,   $launch_dir);

-d $candidate or die "candidate directory not found: $candidate\n";
$candidate = abs_path($candidate);
my $candidate_version = candidate_version($candidate);
-f $inventory or die "inventory not found: $inventory\n";
system("cpanm", "--version") == 0 or die "cpanm is required\n";

open my $ifh, "<", $inventory or die "$inventory: $!";
local $/;
my $data = decode_json(<$ifh>);
close $ifh;

my @entries = @{ $data->{distributions} || [] };
@entries = grep { $_->{distribution} eq $only } @entries if defined $only;
die "no downstream distributions selected\n" unless @entries;

remove_tree($work) if -d $work;
make_path($work, $results);
my $local = abs_path(File::Spec->catdir($work, "local"));
make_path($local);

my %env = (
    PERL5LIB => File::Spec->catdir($local, "lib", "perl5"),
    PERL_LOCAL_LIB_ROOT => $local,
    PERL_MB_OPT => "--install_base $local",
    PERL_MM_OPT => "INSTALL_BASE=$local",
);

run_or_die("candidate.log", \%env,
    "cpanm", "--notest", "--local-lib-contained", $local, "--installdeps", $candidate);
run_in_dir_or_die("candidate.log", \%env, $candidate, $^X, "Build.PL");
run_in_dir_or_die("candidate.log", \%env, $candidate, File::Spec->catfile(".", "Build"));
run_in_dir_or_die("candidate.log", \%env, $candidate, File::Spec->catfile(".", "Build"), "test");
run_in_dir_or_die("candidate.log", \%env, $candidate, File::Spec->catfile(".", "Build"), "install");

my @summary;
for my $entry (@entries) {
    my $dist = $entry->{distribution};
    my $release = $entry->{release};
    my $target = $entry->{cpan_target} || $dist;
    my $log = safe_name($dist) . ".log";
    my $rc = run($log, \%env, undef, "cpanm", "--local-lib-contained", $local, "--test-only", $target);
    push @summary, {
        distribution => $dist,
        release => $release,
        cpan_target => $target,
        perl => sprintf("%vd", $^V),
        os => $^O,
        archname => $Config{archname},
        candidate_version => $candidate_version,
        baseline_tag => $data->{baseline_tag},
        status => $rc == 0 ? "pass" : "blocked",
        exit_code => $rc,
        log => $log,
        note => $rc == 0 ? undef : "Provisional: compare with cpan-0.009 before classification.",
    };
}

my $summary_file = File::Spec->catfile($results, "summary.json");
open my $sfh, ">", $summary_file or die "$summary_file: $!";
print {$sfh} JSON::PP->new->canonical->pretty->encode({
    schema_version => 1,
    snapshot_date => $data->{snapshot_date},
    candidate_dir => $candidate,
    results => \@summary,
});
close $sfh;
print "wrote $summary_file\n";
exit(grep({ $_->{status} ne "pass" } @summary) ? 1 : 0);

sub run_or_die {
    my ($log, $env, @cmd) = @_;
    my $rc = run($log, $env, undef, @cmd);
    die "command failed (exit $rc); see $results/$log\n" if $rc;
}

sub run_in_dir_or_die {
    my ($log, $env, $dir, @cmd) = @_;
    my $rc = run($log, $env, $dir, @cmd);
    die "command failed (exit $rc); see $results/$log\n" if $rc;
}

sub run {
    my ($log, $env, $dir, @cmd) = @_;
    my $path = File::Spec->catfile($results, $log);
    open my $fh, ">>", $path or die "$path: $!";
    print {$fh} "\n\$ ", join(" ", map { shell_quote($_) } @cmd), "\n";
    close $fh;
    local %ENV = (%ENV, %$env);
    my $pid = fork();
    die "fork failed: $!" unless defined $pid;
    if ($pid == 0) {
        chdir $dir or die "chdir $dir: $!" if defined $dir;
        open STDOUT, ">>", $path or die "$path: $!";
        open STDERR, ">&", \*STDOUT or die "dup stdout: $!";
        exec @cmd or die "exec $cmd[0]: $!";
    }
    my $waited = waitpid($pid, 0);
    return 255 if $waited == -1;
    my $status = $?;
    return 128 + WTERMSIG($status) if WIFSIGNALED($status);
    return WEXITSTATUS($status) if WIFEXITED($status);
    return 255;
}

sub candidate_version {
    my ($dir) = @_;
    my $pm = File::Spec->catfile($dir, qw(lib Devel CallChecker.pm));
    open my $fh, "<", $pm or die "$pm: $!";
    while (my $line = <$fh>) {
        return $1 if $line =~ /\bour\s+\$VERSION\s*=\s*["']([^"']+)["']/;
    }
    die "could not determine candidate version from $pm\n";
}

sub safe_name {
    my ($s) = @_;
    $s =~ s/[^A-Za-z0-9_.-]+/_/g;
    return $s;
}

sub shell_quote {
    my ($s) = @_;
    return "''" if !defined($s) || $s eq "";
    return $s if $s =~ /\A[-A-Za-z0-9_.,:\/=@+]+\z/;
    $s =~ s/'/'"'"'/g;
    return "'$s'";
}

sub usage {
    print "Usage: $0 [--only Distribution] [--candidate DIR] [--inventory FILE] [--work DIR] [--results DIR]\n";
    exit 0;
}
