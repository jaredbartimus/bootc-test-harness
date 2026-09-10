Name:           dummy-test
Version:        0.1
Release:        1
Summary:        Minimal dummy test package for bootc-test-harness integration test
License:        Apache-2.0
BuildArch:      noarch

%description
Minimal dummy test package for bootc-test-harness integration test.

%prep

%build

%install
mkdir -p %{buildroot}/etc
echo "dummy-test-installed" > %{buildroot}/etc/dummy-test.conf

%files
/etc/dummy-test.conf
