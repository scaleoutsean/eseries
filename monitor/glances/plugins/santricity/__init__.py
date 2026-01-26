#
# This plugin may be added to Glances (https://nicolargo.github.io/glances/).
# It is provided under multiple licenses to match Glances' licensing, but not limit its use:
# SPDX-License-Identifier: LGPL-3.0, MIT, Apache 2.0
# SPDX-FileCopyrightText: 2026 scaleoutSean@Github
#
# Glances SANtricity plugin for SANtricity systems 11.90+
# The plugin uses basic authentication to connect to the SANtricity REST API.
# It retrieves system health, IOPS, throughput, capacity, volume count, and failure information
# Main use case is monitoring NetApp E-Series and EF-Series storage arrays for DAS environments
# For SAN environments it is suggested to use E-Series Performance Analyzer or E-Series SANtricity Collector
# Note: This plugin requires the 'requests' library which may already be included in Glances dependencies.
# https://github.com/nicolargo/glances/blob/263f4121f10c3561ad95dcd89979992073fc60fb/all-requirements.txt#L179
# In absence of upstream integration, this plugin can be placed in the Glances plugins directory.
# cp -r santricity /path/to/glances/plugins/
# Configure the plugin in glances.conf under [santricity] section (/conf/glances.conf in glances source)
# [santricity]
# host = 10.1.249.1,10.1.250.1
# username = monitor
# password = your_password
# verify_ssl = False


"""SANtricity plugin."""

import json
import random

try:
    import requests
except ImportError:
    requests = None

from glances.logger import logger
from glances.plugins.plugin.model import GlancesPluginModel

# Fields description
fields_description = {
    'name': {'description': 'System name'},
    'status': {'description': 'Health status'},
    'read_iops': {'description': 'Read IOPS', 'unit': 'number'},
    'write_iops': {'description': 'Write IOPS', 'unit': 'number'},
    'read_throughput': {'description': 'Read throughput', 'unit': 'bytepersecond'},
    'write_throughput': {'description': 'Write throughput', 'unit': 'bytepersecond'},
    'free_capacity': {'description': 'Free capacity', 'unit': 'byte'},
    'used_capacity': {'description': 'Used capacity', 'unit': 'byte'},
    'total_capacity': {'description': 'Total capacity', 'unit': 'byte'},
    'volumes_count': {'description': 'Number of volumes', 'unit': 'number'},
    'failures_count': {'description': 'Number of failures', 'unit': 'number'},
}


class Plugin(GlancesPluginModel):
    """Glances SANtricity plugin."""

    def __init__(self, args=None, config=None):
        """Init the plugin."""
        super().__init__(
            args=args,
            config=config,
            stats_init_value={},
            fields_description=fields_description,
        )

        # We want to display the stat in the curse interface
        self.display_curse = True

        # Init configuration variables
        self.controllers = []
        # Best practice: use the monitor (read-only) SANtricity account
        self.username = "monitor"
        self.password = ""
        # Add TLS certificate to OS or container trust store for verification
        self.verify_ssl = False

        if config:
            # Parse controllers list
            # Can be defined as a list ["1.1.1.1", "2.2.2.2"] or string 1.1.1.1,2.2.2.2 (single controller also works)
            c_list = config.get_value('santricity', 'host')
            if c_list:
                try:
                    # Try to parse as JSON list
                    self.controllers = json.loads(c_list.replace("'", '"'))
                except ValueError:
                    # Fallback to comma separated string
                    self.controllers = [c.strip() for c in c_list.replace('[', '').replace(']', '').split(',')]

            self.username = config.get_value('santricity', 'username')
            self.password = config.get_value('santricity', 'password')
            self.verify_ssl = config.get_bool_value('santricity', 'verify_ssl', default=False)
        
        # Log if requests is missing
        if requests is None:
            logger.error("Santricity plugin - requests library not found")

    def get_key(self):
        """Return the key of the list."""
        return 'name'

    @GlancesPluginModel._check_decorator
    @GlancesPluginModel._log_result_decorator
    def update(self):
        """Update SANtricity stats."""
        if not requests or not self.controllers:
            return self.stats

        # Pick a random controller
        controller = random.choice(self.controllers)
        
        # Build base URL (assuming controller IP provided in config)
        # API endpoints: "/devmgr/v2/storage-systems/1" suffixed to https:// + controller IP + :8443
        # Format: https://{controller}:8443
        base_url = f"https://{controller}:8443/devmgr/v2/storage-systems/1"
        
        auth = (self.username, self.password)
        stats = {}
        
        try:
            # 1. Get System Info (Capacity, Status, Name)
            # Validates connection
            r = requests.get(base_url, auth=auth, verify=self.verify_ssl, timeout=5)
            if r.status_code == 200:
                data = r.json()
                stats['name'] = data.get('name', 'Unknown')
                stats['status'] = data.get('status', 'Unknown')
                
                # Capacity (convert string to float/int - assuming bytes)
                free = float(data.get('freePoolSpaceAsString', 0))
                used = float(data.get('usedPoolSpaceAsString', 0))
                stats['free_capacity'] = int(free)
                stats['used_capacity'] = int(used)
                stats['total_capacity'] = int(free + used)
            else:
                logger.debug(f"Santricity system info failed {r.status_code}")
                return self.stats

            # 2. Get Statistics (IOPS, Throughput)
            r = requests.get(f"{base_url}/analysed-system-statistics", auth=auth, verify=self.verify_ssl, timeout=5)
            if r.status_code == 200:
                data = r.json()
                stats['read_iops'] = int(float(data.get('readIOps', 0)))
                stats['write_iops'] = int(float(data.get('writeIOps', 0)))
                # Assuming throughput is in bytes/sec
                stats['read_throughput'] = int(float(data.get('readThroughput', 0)))
                stats['write_throughput'] = int(float(data.get('writeThroughput', 0)))

            # 3. Get Failures
            stats['failures_count'] = None
            r = requests.get(f"{base_url}/failures?details=false", auth=auth, verify=self.verify_ssl, timeout=5)
            if r.status_code == 200:
                data = r.json()
                if isinstance(data, list):
                    stats['failures_count'] = len(data)
                
            # 4. Get Volumes Count
            r = requests.get(f"{base_url}/volumes", auth=auth, verify=self.verify_ssl, timeout=5)
            if r.status_code == 200:            
                data = r.json()
                if isinstance(data, list):
                    stats['volumes_count'] = len(data)

        except Exception as e:
            logger.error(f"Santricity plugin error: {e}")
            return self.stats

        self.stats = stats
        return self.stats

    def update_views(self):
        """Update stats views."""
        super().update_views()

        if not self.stats:
            return

        # Failures decoration
        # above 0 is red, zero is green, None is amber
        fail_count = self.stats.get('failures_count')
        
        if fail_count is None:
            self.views['failures_count']['decoration'] = 'WARNING'
        elif fail_count > 0:
            self.views['failures_count']['decoration'] = 'CRITICAL'
        else:
            self.views['failures_count']['decoration'] = 'OK'

        # Status decoration
        status = self.stats.get('status')
        if status == 'needsAttn':
            self.views['status']['decoration'] = 'CRITICAL'
        elif status == 'optimal': # 'optimal' is good
            self.views['status']['decoration'] = 'OK'
        else:
            # Default to WARNING if not needsAttn and not optimal
            self.views['status']['decoration'] = 'WARNING'
