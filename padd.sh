#!/usr/bin/env sh

# Pi-hole: A black hole for Internet advertisements
# (c) Pi-hole (https://pi-hole.net)
# Network-wide ad blocking via your own hardware.
#
# PADD
# A more advanced version of the chronometer provided with Pihole
#
# This file is copyright under the latest version of the EUPL.
# Please see LICENSE file for your rights under this license.

# SETS LOCALE
export LC_ALL=C
export LC_NUMERIC=C

############################################ VARIABLES #############################################

# VERSION
padd_version="v4.2.1"

# LastChecks
LastCheckPADDInformation=$(date +%s)
LastCheckFullInformation="${LastCheckPADDInformation}"
LastCheckNetworkInformation="${LastCheckPADDInformation}"

# padd_data holds the data returned by FTL's /padd endpoint globally
padd_data=""

# should PADD run only once?
runOnce=false

# COLORS
CSI="$(printf '\033')["  # Control Sequence Introducer
red_text="${CSI}91m"     # Red
green_text="${CSI}92m"   # Green
yellow_text="${CSI}93m"  # Yellow
blue_text="${CSI}94m"    # Blue
magenta_text="${CSI}95m" # Magenta
cyan_text="${CSI}96m"    # Cyan
reset_text="${CSI}0m"    # Reset to default
clear_line="${CSI}0K"    # Clear the current line to the right to wipe any artifacts remaining from last print

# STYLES
bold_text="${CSI}1m"
blinking_text="${CSI}5m"
dim_text="${CSI}2m"

# CHECK BOXES
check_box_good="[${green_text}✓${reset_text}]"       # Good
check_box_bad="[${red_text}✗${reset_text}]"          # Bad
check_box_disabled="[${blue_text}-${reset_text}]"    # Disabled, but not an error
check_box_question="[${yellow_text}?${reset_text}]"  # Question / ?
check_box_info="[${yellow_text}i${reset_text}]"      # Info / i

# PICO STATUSES
pico_status_ok="${check_box_good} Sys. OK"
pico_status_update="${check_box_info} Update"
pico_status_hot="${check_box_bad} Sys. Hot!"
pico_status_off="${check_box_info} No blck"
pico_status_ftl_down="${check_box_bad} No CXN"
pico_status_dns_down="${check_box_bad} DNS Down"

# MINI STATUS
mini_status_ok="${check_box_good} System OK"
mini_status_update="${check_box_info} Update avail."
mini_status_hot="${check_box_bad} System is hot!"
mini_status_off="${check_box_info} No blocking!"
mini_status_ftl_down="${check_box_bad} No connection!"
mini_status_dns_down="${check_box_bad} DNS off!"

# REGULAR STATUS
full_status_ok="${check_box_good} System is healthy"
full_status_update="${check_box_info} Updates are available"
full_status_hot="${check_box_bad} System is hot!"
full_status_off="${check_box_info} Blocking is disabled"
full_status_ftl_down="${check_box_bad} No connection!"
full_status_dns_down="${check_box_bad} DNS is off!"

# MEGA STATUS
mega_status_ok="${check_box_good} Your system is healthy"
mega_status_update="${check_box_info} Updates are available"
mega_status_hot="${check_box_bad} Your system is hot!"
mega_status_off="${check_box_info} Blocking is disabled!"
mega_status_ftl_down="${check_box_bad} No connection to FTL!"
mega_status_dns_down="${check_box_bad} Pi-hole's DNS server is off!"

# TINY STATUS
tiny_status_ok="${check_box_good} System is healthy"
tiny_status_update="${check_box_info} Updates are available"
tiny_status_hot="${check_box_bad} System is hot!"
tiny_status_off="${check_box_info} Blocking is disabled"
tiny_status_ftl_down="${check_box_bad} No connection to FTL!"
tiny_status_dns_down="${check_box_bad} DNS is off!"

# Text only "logos"
padd_text="${green_text}${bold_text}PADD${reset_text}"

# PADD logos - regular and retro
padd_logo_1="${bold_text} ${yellow_text}_${green_text}_      ${blue_text}_${magenta_text}_  ${yellow_text}_${green_text}_   ${reset_text}"
padd_logo_2="${bold_text}${yellow_text}|${green_text}_${blue_text}_${cyan_text}) ${red_text}/${yellow_text}\\ ${blue_text}|  ${red_text}\\${yellow_text}|  ${cyan_text}\\  ${reset_text}"
padd_logo_3="${bold_text}${green_text}|   ${red_text}/${yellow_text}-${green_text}-${blue_text}\\${cyan_text}|${magenta_text}_${red_text}_${yellow_text}/${green_text}|${blue_text}_${cyan_text}_${magenta_text}/  ${reset_text}"

############################################# FTL ##################################################

TestAPIAvailability() {

    local chaos_api_list authResponse digReturnCode authStatus authData apiAvailable prefix rest port_and_path nl last_api_list


    # Assume no working API until one answers
    apiAvailable=false
    startup_error=""

    # Check if an API location was specified with --api
    if [ -n "${API_LOCATION}" ]; then
        # Normalize --api to always end with a single trailing '/' without forking
        if [ "${API_LOCATION}" = "/" ]; then
            chaos_api_list="/"
        else
            chaos_api_list="${API_LOCATION%/}/"
        fi
    else
        # Query the API URLs from FTL using CHAOS TXT
        # The result is a space-separated enumeration of full URLs
        # e.g., "http://localhost:80/api" or "https://domain.com:443/api"
        if [ -z "${SERVER}" ] || [ "${SERVER}" = "localhost" ] || [ "${SERVER}" = "127.0.0.1" ]; then
            # --server was not set or set to local, assuming we're running locally
            chaos_api_list="$(dig +short chaos txt local.api.ftl @localhost 2>&1)"
        else
            # --server was set, try to get response from there
            chaos_api_list="$(dig +short chaos txt domain.api.ftl @"${SERVER}" 2>&1)"
        fi
        digReturnCode=$?

        if [ "${digReturnCode}" != "0" ]; then
            # If the query was not successful
            startup_error="API not available. Please check server address and connectivity"
            return 1
        fi

        # Keep only the first line of dig's output (mirrors head -n 1 without forking)
        nl='
'
        chaos_api_list="${chaos_api_list%%"${nl}"*}"
    fi

    # Iterate over space-separated list of URLs
    while [ -n "${chaos_api_list}" ]; do
        # Get the first URL
        API_URL="${chaos_api_list%% *}"
        # Strip leading and trailing quotes
        API_URL="${API_URL%\"}"
        API_URL="${API_URL#\"}"

        # If $SERVER is user-specified by IP, the returned API_URL might contain a domain which can't be resolved by the host
        # Therefore, we substitute the domain with the IP
        if [ -n "${SERVER}" ]; then
            case "${API_URL}" in
                http://*)
                    prefix="http://"
                    rest="${API_URL#http://}"
                    ;;
                https://*)
                    prefix="https://"
                    rest="${API_URL#https://}"
                    ;;
                *)
                    rest=""
                    ;;
            esac

            # Only rewrite the host when a numeric port appears before the first '/'
            case "${rest%%/*}" in
                *:[0-9]*)
                    port_and_path=":${rest#*:}"

                    # Check if SERVER is an IPv6
                    case "${SERVER}" in
                        *:*)
                            # Replace the domain with the IP
                            # Add square brackets for IPv6 (as recommended by RFC2732)
                            API_URL="${prefix}[${SERVER}]${port_and_path}"
                            ;;
                        *)
                            # Replace the domain with the IP
                            API_URL="${prefix}${SERVER}${port_and_path}"
                            ;;
                    esac
                    ;;
            esac
        fi

        # Test if the API is available at this URL, include delimiter for ease in splitting payload
        authResponse=$(curl --connect-timeout 2 --max-time 10 -skS -w ">>%{http_code}" "${API_URL}auth")

        # authStatus is the response http_code, eg. 200, 401.
        # Shell parameter expansion, remove everything up to and including the >> delim
        authStatus=${authResponse#*>>}
        # data is everything from response
        # Shell parameter expansion, remove the >> delim and everything after
        authData=${authResponse%>>*}

        # Test if http status code was 200 (OK) or 401 (authentication required)
        if [ "${authStatus}" = 200 ]; then
            # API is available without authentication
            apiAvailable=true
            needAuth=false
            break

        elif [ "${authStatus}" = 401 ]; then
            # API is available with authentication
            apiAvailable=true
            needAuth=true
            # Check if 2FA is required (heredoc avoids a subshell pipe)
            needTOTP=$(jq --raw-output .session.totp 2>/dev/null <<EOF
${authData}
EOF
)
            break
        else
            # API is not available at this port/protocol combination
            apiAvailable=false

            # Remove the first URL from the list
            last_api_list="${chaos_api_list}"
            chaos_api_list="${chaos_api_list#* }"

            # If the list did not change, we are at the last element
            if [ "${last_api_list}" = "${chaos_api_list}" ]; then
                # Remove the last element
                chaos_api_list=""
            fi
        fi
    done

    # if apiAvailable is false, no working API was found
    if [ "${apiAvailable}" = false ]; then
        startup_error="API not available. Please check FTL.log"
        return 1
    fi
}

LoginAPI() {
    # Exit early if no authentication is required
    if [ "${needAuth}" = false ]; then
        moveXOffset; echo "No authentication required."
        return
    fi

    # Check if we are running locally before checking for the CLI password
    if [ -z "${SERVER}" ] || [ "${SERVER}" = "localhost" ] || [ "${SERVER}" = "127.0.0.1" ]; then
        # Try to read the CLI password (if enabled and readable by the current user)
        if [ -r /etc/pihole/cli_pw ]; then
            read -r password < /etc/pihole/cli_pw
            # If we can read the CLI password, we can skip 2FA even when it's required otherwise
            needTOTP=false
        fi
    fi

    if [ -z "${password}" ]; then
        # no password was supplied as argument or read from CLI file
        moveXOffset; echo "No password supplied. Please enter your password:"
        # secretly read the password
        moveXOffset; secretRead; printf '\n'
    fi

    if [ "${needTOTP}" = true ] && [ -z "${totp}" ]; then
        # 2FA required, but no TOTP was supplied as argument
        moveXOffset; echo "Please enter the correct second factor."
        moveXOffset; echo "(Can be any number if you used the app password)"
        moveXOffset; read -r totp
    fi

    # Try to authenticate using the supplied password (CLI file, argument or user input) and TOTP
    if ! Authenticate; then
        return 1
    fi

    # Try to login again until the session is valid
    while [ "${validSession}" != true ]  ; do
        moveXOffset; echo "Authentication failed."

        # Print the error message if there is one
        if  [ "${sessionError}" != "null"  ]; then
            moveXOffset; echo "Error: ${sessionError}"
        fi
        # Print the session message if there is one
        if  [ "${sessionMessage}" != "null"  ]; then
            moveXOffset; echo "Error: ${sessionMessage}"
        fi

        moveXOffset; echo "Please enter the correct password:"

        # secretly read the password
        moveXOffset; secretRead; printf '\n'

        if [ "${needTOTP}" = true ]; then
            moveXOffset; echo "Please enter the correct second factor:"
            moveXOffset; echo "(Can be any number if you used the app password)"
            moveXOffset; read -r totp
        fi

        # Try to authenticate again
        if ! Authenticate; then
            return 1
        fi
    done

    # Loop exited, authentication was successful
    moveXOffset; echo "Authentication successful."

}

DeleteSession() {
    local deleteResponse
    # if a valid Session exists (no password required or successful authentication) and
    # SID is non-empty and not "null" (successful authentication only), delete the session
    if [ "${validSession}" = true ] && [ -n "${SID}" ] && [ "${SID}" != "null" ]; then
        # Try to delete the session. Omit the output, but get the http status code
        # SID is passed via stdin config (-K -) to prevent leakage via process information
        deleteResponse=$(curl --connect-timeout 2 --max-time 10 -skS -o /dev/null -w "%{http_code}" -X DELETE "${API_URL}auth" \
            -H "Accept: application/json" \
            -K - <<EOF
header = "sid: ${SID}"
EOF
)

        printf "\n\n"
        case "${deleteResponse}" in
            "204") moveXOffset; printf "%b" "Session successfully deleted.\n";;
            "401") moveXOffset; printf "%b" "Logout attempt without a valid session. Unauthorized!\n";;
         esac;
    else
        # no session to delete, just print a newline for nicer output
        echo
    fi

}

Authenticate() {
    local auth_parsed nl sessionResponse
    startup_error=""

    # JSON-encode the password via stdin (printf is a shell builtin, so the password
    # stays out of ps) and pipe straight into curl --data-binary @- without a temp file.
    sessionResponse="$(printf '{"password":%s,"totp":%s}' \
        "$(printf '%s' "${password}" | jq -Rs .)" "${totp:-null}" \
        | curl --connect-timeout 2 --max-time 10 -skS -X POST "${API_URL}auth" \
            --user-agent "PADD ${padd_version}" \
            -H "Content-Type: application/json" \
            --data-binary @-
    )"

    if [ -z "${sessionResponse}" ]; then
        startup_error="No response from FTL server. Please check connectivity and use the options to set the API URL. Usage: $0 [--server <domain|IP>] or [--api <API URL>]"
        return 1
    fi

    nl='
'
    # Obtain validity, session ID, sessionMessage, and error message in a single jq pass,
    # then split the 4 newline-delimited values via POSIX parameter expansion (no subshells)
    auth_parsed=$(jq -r '
        (.session.valid | tostring),
        (.session.sid | tostring),
        (.session.message | tostring),
        (.error.message | tostring)
    ' 2>/dev/null <<EOF
${sessionResponse}
EOF
)
    validSession="${auth_parsed%%"${nl}"*}"
    auth_parsed="${auth_parsed#*"${nl}"}"
    SID="${auth_parsed%%"${nl}"*}"
    auth_parsed="${auth_parsed#*"${nl}"}"
    sessionMessage="${auth_parsed%%"${nl}"*}"
    sessionError="${auth_parsed#*"${nl}"}"
}

# Queries an FTL API endpoint and stores the result in global `ftl_result`
# (JSON payload on HTTP 200, "401" if unauthorized, "000" on connection/HTTP error)
# to avoid a subshell capture on every 5-second refresh.
GetFTLData() {
    local response
    local data
    local status

    # get the data from querying the API as well as the http status code, include delimiter for ease in splitting payload
    # SID is passed via stdin config (-K -) to prevent leakage via process information
    response=$(curl --connect-timeout 2 --max-time 10 -sk -w ">>%{http_code}" -X GET "${API_URL}$1$2" \
        -H "Accept: application/json" \
        -K - <<EOF
header = "sid: ${SID}"
EOF
)

    # status is the response http_code, eg. 200, 401.
    # Shell parameter expansion, remove everything up to and including the >> delim
    status=${response#*>>}
    # data is everything from response
    # Shell parameter expansion, remove the >> delim and everything after
    data=${response%>>*}

    ftl_result=""
    if [ "${status}" = 200 ]; then
        ftl_result="${data}"
    elif [ "${status}" = 401 ]; then
        # unauthorized
        ftl_result="401"
    else
        # connection lost or unexpected HTTP error (e.g., 000, 502, 503)
        ftl_result="000"
    fi
}

############################################# GETTERS ##############################################

GetPADDData() {
    local response
    GetFTLData "padd" "$1"
    response="${ftl_result}"

    if [ "${response}" = 000 ]; then
        # connection lost
        padd_data="000"
    elif [ "${response}" = 401 ]; then
        # unauthorized
        padd_data="401"
    elif [ -z "${response}" ]; then
        # empty payload
        padd_data=""
    else
        # Iterate over all the leaf paths in the JSON object and creates key-value
        # pairs in the format "key=value". Nested objects are flattened using the dot
        # notation, e.g., { "a": { "b": 1 } } becomes "a.b=1".
        # We cannot use leaf_paths here as it was deprecated in jq 1.6 and removed in
        # current master
        # Using "paths(scalars | true)" will return null and false values.
        # We also check if the value is exactly `null` and, in this case, return the
        # string "null", as jq would return an empty string for nulls.
        # 'tostring' is necessary because jq < 1.6 does not convert numbers and bools automatically
        padd_data=$(jq -r 'paths(scalars | true) as $p | [[$p | .[] | tostring] | join(".")] + [if getpath($p)!=null then (getpath($p) | tostring) else "null" end] | join("=")' 2>/dev/null <<EOF
${response}
EOF
)
    fi
}

GetPADDValue() {
    # Usage: GetPADDValue <key> <variable>
    # Sets <variable> to the value for <key> (empty if missing) in a single call
    # without grep/awk. Rejects invalid variable names before eval.
    case "$2" in ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;; esac
    local padd_value nl val
    padd_value=""
    nl='
'
    # Wrap padd_data in newlines so exact key matching works via POSIX case pattern
    case "${nl}${padd_data}${nl}" in
        *"${nl}$1="*)
            val="${nl}${padd_data}${nl}"
            val="${val#*"${nl}$1="}"
            # shellcheck disable=SC2034
            padd_value="${val%%"${nl}"*}"
            # padd_value is referenced via eval below
            ;;
    esac
    eval "$2=\${padd_value}"
}

GetSummaryInformation() {
    local domains_being_blocked_raw dns_queries_today_raw ads_blocked_today_raw ads_percentage_today_raw dns_queries_frequency_raw privacy_level
    if [ "${connection_down_flag}" = true ]; then
        clients="N/A"
        blocking_enabled="N/A"
        domains_being_blocked="N/A"
        dns_queries_today="N/A"
        ads_blocked_today="N/A"
        ads_percentage_today="N/A"
        cache_size="N/A"
        cache_evictions="N/A"
        cache_inserts="N/A"
        latest_blocked_raw="N/A"
        top_blocked_raw="N/A"
        top_domain_raw="N/A"
        top_client_raw="N/A"
        dns_queries_frequency="N/A"
        dns_query_rate_label="Qrs/min:"
        return
    fi

    GetPADDValue active_clients clients
    GetPADDValue blocking blocking_enabled
    GetPADDValue gravity_size domains_being_blocked_raw
    GetPADDValue queries.total dns_queries_today_raw
    GetPADDValue queries.blocked ads_blocked_today_raw
    GetPADDValue queries.percent_blocked ads_percentage_today_raw
    GetPADDValue cache.size cache_size
    GetPADDValue cache.evicted cache_evictions
    GetPADDValue cache.inserted cache_inserts
    GetPADDValue recent_blocked latest_blocked_raw
    GetPADDValue top_blocked top_blocked_raw
    GetPADDValue top_domain top_domain_raw
    GetPADDValue top_client top_client_raw
    GetPADDValue queries.query_frequency dns_queries_frequency_raw
    GetPADDValue config.privacy_level privacy_level

    # Normalize empty / "null" text fields to "N/A"
    if [ -z "${clients}" ] || [ "${clients}" = "null" ]; then clients="N/A"; fi
    if [ -z "${blocking_enabled}" ] || [ "${blocking_enabled}" = "null" ]; then blocking_enabled="N/A"; fi
    if [ -z "${cache_size}" ] || [ "${cache_size}" = "null" ]; then cache_size="N/A"; fi
    if [ -z "${cache_evictions}" ] || [ "${cache_evictions}" = "null" ]; then cache_evictions="N/A"; fi
    if [ -z "${cache_inserts}" ] || [ "${cache_inserts}" = "null" ]; then cache_inserts="N/A"; fi
    if [ -z "${latest_blocked_raw}" ] || [ "${latest_blocked_raw}" = "null" ]; then latest_blocked_raw="N/A"; fi
    if [ -z "${top_blocked_raw}" ] || [ "${top_blocked_raw}" = "null" ]; then top_blocked_raw="N/A"; fi
    if [ -z "${top_domain_raw}" ] || [ "${top_domain_raw}" = "null" ]; then top_domain_raw="N/A"; fi
    if [ -z "${top_client_raw}" ] || [ "${top_client_raw}" = "null" ]; then top_client_raw="N/A"; fi

    # Normalize empty / "null" numeric fields to 0 before formatting/math
    if [ -z "${domains_being_blocked_raw}" ] || [ "${domains_being_blocked_raw}" = "null" ]; then domains_being_blocked_raw=0; fi
    if [ -z "${dns_queries_today_raw}" ] || [ "${dns_queries_today_raw}" = "null" ]; then dns_queries_today_raw=0; fi
    if [ -z "${ads_blocked_today_raw}" ] || [ "${ads_blocked_today_raw}" = "null" ]; then ads_blocked_today_raw=0; fi
    if [ -z "${ads_percentage_today_raw}" ] || [ "${ads_percentage_today_raw}" = "null" ]; then ads_percentage_today_raw=0; fi
    if [ -z "${dns_queries_frequency_raw}" ] || [ "${dns_queries_frequency_raw}" = "null" ]; then dns_queries_frequency_raw=0; fi
    if [ -z "${privacy_level}" ] || [ "${privacy_level}" = "null" ]; then privacy_level=0; fi

    domains_being_blocked=$(printf "%.f" "${domains_being_blocked_raw}")
    dns_queries_today=$(printf "%.f" "${dns_queries_today_raw}")
    ads_blocked_today=$(printf "%.f" "${ads_blocked_today_raw}")
    ads_percentage_today=$(printf "%.1f" "${ads_percentage_today_raw}")
    
    dns_queries_frequency=$(awk -v f="${dns_queries_frequency_raw}" 'BEGIN {
        val = sprintf("%.f", f * 60)
        if (val == "-0") val = "0"
        print val
    }')

    if awk -v q="${dns_queries_frequency}" 'BEGIN { exit !((q + 0) > 100) }'; then
        dns_query_rate_label="Qrs/sec:"
        dns_queries_frequency=$(awk -v f="${dns_queries_frequency_raw}" 'BEGIN {
            freq = f + 0
            if (freq > 10) printf "%.0f\n", freq
            else if (freq < 1) printf "%.2f\n", freq
            else printf "%.1f\n", freq
        }')
    else
        dns_query_rate_label="Qrs/min:"
        dns_queries_frequency=$(awk -v q="${dns_queries_frequency}" 'BEGIN {
            freq = q + 0
            if (freq > 10) printf "%.0f\n", freq
            else if (freq < 1) printf "%.2f\n", freq
            else printf "%.1f\n", freq
        }')
    fi

    # Substitute values returned by FTL for privacy level >= 1 / >= 2
    if [ "${privacy_level}" -ge 1 ]; then
        top_domain_raw="hidden by privacy level"
        top_blocked_raw="hidden by privacy level"
        latest_blocked_raw="hidden by privacy level"
    fi
    if [ "${privacy_level}" -ge 2 ]; then
        top_client_raw="hidden by privacy level"
    fi
}

GetSystemInformation() {
    local cpu_temp_raw cpu_temp temp_unit cpu_temp_celsius temp_conv hot_limit core_count cpu_load_1_raw cpu_load_5_raw cpu_load_15_raw cpu_percent_raw memory_percent_raw memory_used_raw memory_total_raw swap_percent_raw
    if [ "${connection_down_flag}" = true ]; then
        system_uptime_raw=0
        temperature="N/A"
        temp_heatmap=${reset_text}

        cpu_load_1="N/A"
        cpu_load_5="N/A"
        cpu_load_15="N/A"
        cpu_load_1_heatmap=${reset_text}
        cpu_load_5_heatmap=${reset_text}
        cpu_load_15_heatmap=${reset_text}
        cpu_percent=0

        memory_percent=0
        memory_heatmap=${reset_text}
        memory_used_total="N/A"

        swap_percent=0
        swap_heatmap=${reset_text}

        sys_model="N/A"
        return
    fi

    # System uptime
    GetPADDValue system.uptime system_uptime_raw
    if [ -z "${system_uptime_raw}" ] || [ "${system_uptime_raw}" = "null" ]; then
        system_uptime_raw=0
    fi

    # CPU temperature and unit
    GetPADDValue sensors.cpu_temp cpu_temp_raw
    if [ -n "${cpu_temp_raw}" ] && [ "${cpu_temp_raw}" != "null" ]; then
        cpu_temp=$(printf "%.1f" "${cpu_temp_raw}")
        GetPADDValue sensors.unit temp_unit
    else
        cpu_temp=""
        temp_unit=""
    fi

    # Temp + Unit
    if [ "${temp_unit}" = "C" ]; then
        temperature="${cpu_temp}°${temp_unit}"
        # no conversion needed
        cpu_temp_celsius="${cpu_temp%%.*}"
        temp_unicode=true
    elif [ "${temp_unit}" = "F" ]; then
        temperature="${cpu_temp}°${temp_unit}"
        # convert to Celsius for limit checking
        temp_conv="$(awk -v t="${cpu_temp}" 'BEGIN { printf "%.6g\n", (t - 32) * 5 / 9 }')"
        if [ -n "${temp_conv}" ]; then
            cpu_temp_celsius="${temp_conv%%.*}"
            if [ "${cpu_temp_celsius}" = "-0" ]; then
                cpu_temp_celsius=0
            fi
        else
            cpu_temp_celsius=-274
        fi
        temp_unicode=true
    elif [ "${temp_unit}" = "K" ]; then
        # no ° for Kelvin
        temperature="${cpu_temp}${temp_unit}"
        # convert to Celsius for limit checking
        temp_conv="$(awk -v t="${cpu_temp}" 'BEGIN { printf "%.6g\n", t - 273.15 }')"
        if [ -n "${temp_conv}" ]; then
            cpu_temp_celsius="${temp_conv%%.*}"
            if [ "${cpu_temp_celsius}" = "-0" ]; then
                cpu_temp_celsius=0
            fi
        else
            cpu_temp_celsius=-274
        fi
        temp_unicode=false
    else # unknown unit
        temperature="N/A"
        # no conversion needed
        cpu_temp_celsius=-274
        temp_unicode=false
    fi

    # CPU temperature heatmap
    GetPADDValue sensors.hot_limit hot_limit
    hot_limit="${hot_limit%%.*}"
    case "${hot_limit}" in
        ''|*[!0-9]*) hot_limit=80 ;;
    esac

    hot_flag=false
    if [ "${cpu_temp_celsius}" -gt "${hot_limit}" ]; then
        temp_heatmap=${blinking_text}${red_text}
        # set flag to change the status message in SetStatusMessage()
        hot_flag=true
    elif [ "${cpu_temp_celsius}" -gt $((hot_limit - 10)) ]; then
        temp_heatmap=${magenta_text}
    elif [ "${cpu_temp_celsius}" -gt $((hot_limit - 20)) ]; then
        temp_heatmap=${blue_text}
    elif [ "${cpu_temp_celsius}" -gt -274 ]; then
        temp_heatmap=${cyan_text}
    else
        temp_heatmap=${reset_text}
    fi

    # CPU, load, heatmap
    GetPADDValue system.cpu.nprocs core_count
    GetPADDValue system.cpu.load.raw.0 cpu_load_1_raw
    GetPADDValue system.cpu.load.raw.1 cpu_load_5_raw
    GetPADDValue system.cpu.load.raw.2 cpu_load_15_raw
    GetPADDValue system.cpu.%cpu cpu_percent_raw
    if [ -z "${cpu_percent_raw}" ] || [ "${cpu_percent_raw}" = "null" ]; then
        GetPADDValue system.cpu.load.percent.0 cpu_percent_raw
    fi

    if [ -z "${core_count}" ] || [ "${core_count}" = "null" ]; then core_count=0; fi
    if [ -z "${cpu_load_1_raw}" ] || [ "${cpu_load_1_raw}" = "null" ]; then cpu_load_1_raw=0; fi
    if [ -z "${cpu_load_5_raw}" ] || [ "${cpu_load_5_raw}" = "null" ]; then cpu_load_5_raw=0; fi
    if [ -z "${cpu_load_15_raw}" ] || [ "${cpu_load_15_raw}" = "null" ]; then cpu_load_15_raw=0; fi
    if [ -z "${cpu_percent_raw}" ] || [ "${cpu_percent_raw}" = "null" ]; then cpu_percent_raw=0; fi

    cpu_load_1=$(printf %.2f "${cpu_load_1_raw}")
    cpu_load_5=$(printf %.2f "${cpu_load_5_raw}")
    cpu_load_15=$(printf %.2f "${cpu_load_15_raw}")
    HeatmapGenerator "${cpu_load_1}" "${core_count}"
    cpu_load_1_heatmap=${heat_out}
    HeatmapGenerator "${cpu_load_5}" "${core_count}"
    cpu_load_5_heatmap=${heat_out}
    HeatmapGenerator "${cpu_load_15}" "${core_count}"
    cpu_load_15_heatmap=${heat_out}
    cpu_percent=$(printf %.1f "${cpu_percent_raw}")
    HeatmapGenerator "${cpu_percent}"
    cpu_percent_heatmap=${heat_out}

    # Memory use and heatmap (bar is generated in GenerateSizeDependentOutput)
    GetPADDValue system.memory.ram.%used memory_percent_raw
    if [ -z "${memory_percent_raw}" ] || [ "${memory_percent_raw}" = "null" ]; then
        memory_percent_raw=0
    fi
    memory_percent=$(printf %.1f "${memory_percent_raw}")
    HeatmapGenerator "${memory_percent}"
    memory_heatmap="${heat_out}"

    GetPADDValue system.memory.ram.used memory_used_raw
    GetPADDValue system.memory.ram.total memory_total_raw
    if [ -n "${memory_used_raw}" ] && [ "${memory_used_raw}" != "null" ] && [ -n "${memory_total_raw}" ] && [ "${memory_total_raw}" != "null" ]; then
        memory_used_total=$(awk -v u="${memory_used_raw}" -v t="${memory_total_raw}" 'BEGIN {
            if (u >= 1048576) us = sprintf("%.1fG", u / 1048576); else us = sprintf("%.0fM", u / 1024);
            if (t >= 1048576) ts = sprintf("%.1fG", t / 1048576); else ts = sprintf("%.0fM", t / 1024);
            printf "%s/%s\n", us, ts
        }')
    else
        memory_used_total="N/A"
    fi

    # Swap use and heatmap (bar is generated in GenerateSizeDependentOutput)
    GetPADDValue system.memory.swap.%used swap_percent_raw
    if [ -z "${swap_percent_raw}" ] || [ "${swap_percent_raw}" = "null" ]; then
        swap_percent_raw=0
    fi
    swap_percent=$(printf %.1f "${swap_percent_raw}")
    HeatmapGenerator "${swap_percent}"
    swap_heatmap="${heat_out}"

    # Get device model
    GetPADDValue host_model sys_model

    # DOCKER_VERSION is set during GetVersionInformation, so this needs to run first during startup
    if [ "${DOCKER_VERSION}" != "null" ]; then
        # Docker image
        sys_model="Container"
    fi

    # Cleaning device model from useless OEM information
    sys_model=$(filterModel "${sys_model}")

    # FTL returns null if device information is not available
    if [ -z "${sys_model}" ] || [ "${sys_model}" = "null" ]; then
        sys_model="N/A"
    fi
}

GetNetworkInformation() {
    local gateway_v4_iface gateway_v6_iface pi_ip4_addrs pi_ip6_addrs DHCP_ACTIVE DHCP_START DHCP_END DHCP_IPv6 PIHOLE_DOMAIN count dns_count DNSSEC CONDITIONAL_FORWARDING tx_bytes_raw tx_bytes_unit rx_bytes_raw rx_bytes_unit
    if [ "${connection_down_flag}" = true ]; then
        iface_name="N/A"
        pi_ip4_addr="N/A"
        pi_ip6_addr="N/A"
        gw_v4_addr="N/A"
        ipv6_status="N/A"
        ipv6_heatmap=${reset_text}
        ipv6_check_box=${check_box_question}

        dhcp_status="N/A"
        dhcp_heatmap=${reset_text}
        dhcp_range="N/A"
        dhcp_range_heatmap=${reset_text}
        dhcp_ipv6_status="N/A"
        dhcp_ipv6_heatmap=${reset_text}
        dhcp_check_box=${check_box_question}

        pi_hostname="N/A"
        full_hostname="N/A"

        dns_count="N/A"
        dns_information="N/A"

        dnssec_status="N/A"
        dnssec_heatmap=${reset_text}

        conditional_forwarding_status="N/A"
        conditional_forwarding_heatmap=${reset_text}

        tx_bytes="N/A"
        rx_bytes="N/A"
        return
    fi

    gateway_v4_iface=""
    gateway_v6_iface=""

    GetPADDValue iface.v4.name gateway_v4_iface
    GetPADDValue iface.v6.name gateway_v6_iface

    # Get IPv4 address of the default interface
    GetPADDValue iface.v4.num_addrs pi_ip4_addrs
    GetPADDValue iface.v4.addr pi_ip4_addr
    if [ -z "${pi_ip4_addrs}" ] || [ "${pi_ip4_addrs}" = "null" ]; then
        pi_ip4_addrs=0
    fi
    if [ "${pi_ip4_addrs}" -eq 0 ] || [ -z "${pi_ip4_addr}" ] || [ "${pi_ip4_addr}" = "null" ]; then
        # No IPv4 address available
        pi_ip4_addr="N/A"
    elif [ "${pi_ip4_addrs}" -gt 1 ]; then
        # More than one IPv4 address available
        pi_ip4_addr="${pi_ip4_addr}+"
    fi

    # Get IPv4 default gateway
    GetPADDValue iface.v4.gw_addr gw_v4_addr
    if [ -z "${gw_v4_addr}" ] || [ "${gw_v4_addr}" = "null" ]; then
        gw_v4_addr="N/A"
    fi

    # Get IPv6 address of the default interface
    GetPADDValue iface.v6.num_addrs pi_ip6_addrs
    GetPADDValue iface.v6.addr pi_ip6_addr
    if [ -z "${pi_ip6_addrs}" ] || [ "${pi_ip6_addrs}" = "null" ]; then
        pi_ip6_addrs=0
    fi
    if [ "${pi_ip6_addrs}" -eq 0 ] || [ -z "${pi_ip6_addr}" ] || [ "${pi_ip6_addr}" = "null" ]; then
        # No IPv6 address available
        pi_ip6_addr="N/A"
        ipv6_check_box=${check_box_disabled}
        ipv6_status="Disabled"
        ipv6_heatmap=${blue_text}
    elif [ "${pi_ip6_addrs}" -eq 1 ]; then
        # One IPv6 address available
        ipv6_check_box=${check_box_good}
        ipv6_status="Enabled"
        ipv6_heatmap=${green_text}
    else
        # More than one IPv6 address available
        pi_ip6_addr="${pi_ip6_addr}+"
        ipv6_check_box=${check_box_good}
        ipv6_status="Enabled"
        ipv6_heatmap=${green_text}
    fi

    # Is Pi-Hole acting as the DHCP server?
    GetPADDValue config.dhcp_active DHCP_ACTIVE

    if [ "${DHCP_ACTIVE}" = "true" ]; then
        GetPADDValue config.dhcp_start DHCP_START
        GetPADDValue config.dhcp_end DHCP_END

        dhcp_status="Enabled"
        dhcp_range="${DHCP_START} - ${DHCP_END}"
        dhcp_range_heatmap=${reset_text}
        dhcp_heatmap=${green_text}
        dhcp_check_box=${check_box_good}

        DHCP_IPv6=""
        # Is DHCP handling IPv6?
        GetPADDValue config.dhcp_ipv6 DHCP_IPv6
        if [ "${DHCP_IPv6}" = "true" ]; then
            dhcp_ipv6_status="Enabled"
            dhcp_ipv6_heatmap=${green_text}
        else
            dhcp_ipv6_status="Disabled"
            dhcp_ipv6_heatmap=${blue_text}
        fi
    else
        dhcp_status="Disabled"
        dhcp_heatmap=${blue_text}
        dhcp_check_box=${check_box_disabled}
        dhcp_range="N/A"

        dhcp_ipv6_status="N/A"
        dhcp_range_heatmap=${yellow_text}
        dhcp_ipv6_heatmap=${yellow_text}
    fi

    # Get hostname
    GetPADDValue node_name pi_hostname
    full_hostname=${pi_hostname}
    # when PI-hole is the DHCP server, append the domain to the hostname
    if [ "${DHCP_ACTIVE}" = "true" ]; then
        GetPADDValue config.dns_domain PIHOLE_DOMAIN
        if [ -n "${PIHOLE_DOMAIN}" ] && [ "${PIHOLE_DOMAIN}" != "null" ] && [ -n "${pi_hostname}" ] && [ "${pi_hostname}" != "null" ]; then
            count=${pi_hostname}"."${PIHOLE_DOMAIN}
            count=${#count}
            if [ "${count}" -lt "18" ]; then
                full_hostname=${pi_hostname}"."${PIHOLE_DOMAIN}
            fi
        fi
    fi

    # Get the number of configured upstream DNS servers
    GetPADDValue config.dns_num_upstreams dns_count
    if [ -z "${dns_count}" ] || [ "${dns_count}" = "null" ]; then
        dns_count=0
    fi
    # if there's only one DNS server
    if [ "${dns_count}" -eq 1 ]; then
        dns_information="1 server"
    else
        dns_information="${dns_count} servers"
    fi

    GetPADDValue config.dns_port ftl_dns_port
    if [ -z "${ftl_dns_port}" ] || [ "${ftl_dns_port}" = "null" ]; then
        dns_port_display="N/A"
    else
        dns_port_display="${ftl_dns_port}"
    fi

    GetPADDValue config.dns_domain PIHOLE_DOMAIN
    if [ -z "${PIHOLE_DOMAIN}" ] || [ "${PIHOLE_DOMAIN}" = "null" ]; then
        dns_domain_display="N/A"
    else
        dns_domain_display="${PIHOLE_DOMAIN}"
    fi

    # DNSSEC
    GetPADDValue config.dns_dnssec DNSSEC
    if [ "${DNSSEC}" = "true" ]; then
        dnssec_status="Enabled"
        dnssec_heatmap=${green_text}
    else
        dnssec_status="Disabled"
        dnssec_heatmap=${blue_text}
    fi

    # Conditional forwarding
    GetPADDValue config.dns_revServer_active CONDITIONAL_FORWARDING
    if [ "${CONDITIONAL_FORWARDING}" = "true" ]; then
        conditional_forwarding_status="Enabled"
        conditional_forwarding_heatmap=${green_text}
    else
        conditional_forwarding_status="Disabled"
        conditional_forwarding_heatmap=${blue_text}
    fi

    # Default interface data (use IPv4 interface - we cannot show both and assume they are the same)
    iface_name="${gateway_v4_iface}"
    GetPADDValue iface.v4.tx_bytes.value tx_bytes_raw
    GetPADDValue iface.v4.tx_bytes.unit tx_bytes_unit
    if [ -z "${tx_bytes_raw}" ] || [ "${tx_bytes_raw}" = "null" ]; then tx_bytes_raw=0; fi
    if [ -z "${tx_bytes_unit}" ] || [ "${tx_bytes_unit}" = "null" ]; then tx_bytes_unit=""; fi
    tx_bytes=$(printf "%.1f %s" "${tx_bytes_raw}" "${tx_bytes_unit}")

    GetPADDValue iface.v4.rx_bytes.value rx_bytes_raw
    GetPADDValue iface.v4.rx_bytes.unit rx_bytes_unit
    if [ -z "${rx_bytes_raw}" ] || [ "${rx_bytes_raw}" = "null" ]; then rx_bytes_raw=0; fi
    if [ -z "${rx_bytes_unit}" ] || [ "${rx_bytes_unit}" = "null" ]; then rx_bytes_unit=""; fi
    rx_bytes=$(printf "%.1f %s" "${rx_bytes_raw}" "${rx_bytes_unit}")

    # If IPv4 and IPv6 interfaces are not the same, add a "*" to the interface
    # name to highlight that there are two different interfaces and the
    # displayed statistics are only for the IPv4 interface, while the IPv6
    # address correctly corresponds to the default IPv6 interface
    if [ -n "${gateway_v4_iface}" ] && [ "${gateway_v4_iface}" != "${gateway_v6_iface}" ]; then
        iface_name="${iface_name}*"
    fi
}

GetPiholeInformation() {
    local ftl_dns_port ftl_cpu_raw ftl_mem_percentage_raw
    if [ "${connection_down_flag}" = true ]; then
        ftl_status="No connection"
        ftl_heatmap=${red_text}
        ftl_check_box=${check_box_bad}
        ftl_cpu="N/A"
        ftl_mem_percentage="N/A"
        ftl_cpu_heatmap=${reset_text}
        ftl_mem_heatmap=${reset_text}
        dns_status="DNS offline"
        dns_heatmap=${red_text}
        dns_check_box=${check_box_bad}
        ftlPID="N/A"
        dns_down_flag=true

        return
    fi

    ftl_dns_port=""
    ftl_status="Running"
    ftl_heatmap=${green_text}
    ftl_check_box=${check_box_good}

    # Get FTL CPU and memory usage
    GetPADDValue "%cpu" ftl_cpu_raw
    GetPADDValue "%mem" ftl_mem_percentage_raw

    ftl_cpu_heatmap=${green_text}
    if [ -z "${ftl_cpu_raw}" ] || [ "${ftl_cpu_raw}" = "null" ]; then
        ftl_cpu="N/A"
        ftl_cpu_heatmap=${yellow_text}
    else
        ftl_cpu="$(printf "%.1f" "${ftl_cpu_raw}")%"
    fi

    ftl_mem_heatmap=${green_text}
    if [ -z "${ftl_mem_percentage_raw}" ] || [ "${ftl_mem_percentage_raw}" = "null" ]; then
        ftl_mem_percentage="N/A"
        ftl_mem_heatmap=${yellow_text}
    else
        ftl_mem_percentage="$(printf "%.1f" "${ftl_mem_percentage_raw}")%"
    fi

    # Get Pi-hole (blocking) status
    GetPADDValue config.dns_port ftl_dns_port
    # Get FTL's current PID
    GetPADDValue pid ftlPID

    # ${ftl_dns_port} == 0 DNS server part of dnsmasq disabled
    dns_down_flag=false
    if [ "${ftl_dns_port}" = 0 ]; then
        dns_status="DNS offline"
        dns_heatmap=${red_text}
        dns_check_box=${check_box_bad}
        # set flag to change the status message in SetStatusMessage()
        dns_down_flag=true
    else
        dns_check_box=${check_box_good}
        dns_status="Active"
        dns_heatmap=${green_text}
    fi
}

# Shortens common custom branch names (fix/, tweak/, new/)
# and assigns the first 7 characters to <variable> without a subshell
ShortenBranch() {
    case "$2" in ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;; esac
    local branch_val="$1"
    local _branch
    case "${branch_val}" in
        fix/*)   _branch="f/${branch_val#fix/}" ;;
        new/*)   _branch="n/${branch_val#new/}" ;;
        tweak/*) _branch="t/${branch_val#tweak/}" ;;
        *)       _branch="${branch_val}" ;;
    esac
    # Trim to 7 chars in-process (mirrors printf '%.7s' without a subshell)
    while [ "${#_branch}" -gt 7 ]; do
        _branch="${_branch%?}"
    done
    # shellcheck disable=SC2034
    eval "$2=\${_branch}"
}

# Normalizes a version string (strips '-*' prerelease suffix and leading 'v')
# and assigns it to <variable> without a subshell
CleanVersion() {
    case "$2" in ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;; esac
    local ver="$1"
    ver="${ver%%-*}"
    # shellcheck disable=SC2034
    ver="${ver#v}"
    eval "$2=\${ver}"
}

# Compares local and remote versions (after stripping '-*' and leading 'v')
# Usage: CompareMasterVersion <local_ver> <remote_ver> <variable>
# Side effect: sets out_of_date_flag="true" if local is behind remote
# Assigns heatmap color (${red_text} or ${green_text}) to <variable> without a subshell
CompareMasterVersion() {
    case "$3" in ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;; esac
    local local_num remote_num color

    local_num="$(VersionConverter "$1")"
    remote_num="$(VersionConverter "$2")"

    # shellcheck disable=SC2034
    if [ "${local_num}" -lt "${remote_num}" ]; then
        out_of_date_flag="true"
        color="${red_text}"
    else
        color="${green_text}"
    fi

    eval "$3=\${color}"
}

GetVersionInformation() {
    local docker_version_converted docker_version_latest_converted CORE_BRANCH CORE_HASH GITHUB_CORE_HASH GITHUB_CORE_VERSION
    local WEB_BRANCH WEB_HASH GITHUB_WEB_HASH GITHUB_WEB_VERSION FTL_BRANCH FTL_HASH GITHUB_FTL_HASH GITHUB_FTL_VERSION CORE_VERSION_raw FTL_VERSION_raw GITHUB_DOCKER_VERSION
    if [ "${connection_down_flag}" = true ]; then
        DOCKER_VERSION=null
        CORE_VERSION="N/A"
        WEB_VERSION="N/A"
        FTL_VERSION="N/A"
        core_version_heatmap=${reset_text}
        web_version_heatmap=${reset_text}
        ftl_version_heatmap=${reset_text}
        return
    fi

    out_of_date_flag="false"

    # Gather DOCKER version information...
    # returns "null" if not running Pi-hole in Docker container
    GetPADDValue version.docker.local DOCKER_VERSION

    # If PADD is running inside docker, immediately return without checking for updated component versions
    if [ "${DOCKER_VERSION}" != "null" ] ; then
        GetPADDValue version.docker.remote GITHUB_DOCKER_VERSION
        docker_version_converted="$(VersionConverter "${DOCKER_VERSION}")"
        docker_version_latest_converted="$(VersionConverter "${GITHUB_DOCKER_VERSION}")"

    # Note: the version comparison will fail for any Docker tag not following a 'YYYY.MM.VV' scheme
    #       e.g. 'nightly', 'beta', 'v6-pre-alpha' and might set a false out_of_date_flag
    #       As those versions are not meant to be used in production, we ignore this small bug
        if [ "${docker_version_converted}" -lt "${docker_version_latest_converted}" ]; then
            out_of_date_flag="true"
            docker_version_heatmap=${red_text}
        else
            docker_version_heatmap=${green_text}
        fi
        return
    fi

    # Gather core version information...
    GetPADDValue version.core.local.branch CORE_BRANCH

    if [ "${CORE_BRANCH}" = "master" ]; then
        GetPADDValue version.core.local.version CORE_VERSION_raw
        CleanVersion "${CORE_VERSION_raw}" CORE_VERSION
        GetPADDValue version.core.remote.version GITHUB_CORE_VERSION
        CompareMasterVersion "${CORE_VERSION}" "${GITHUB_CORE_VERSION}" core_version_heatmap
    else
        # Custom branch
        if [ -z "${CORE_BRANCH}"  ]; then
            # Branch name is empty, something went wrong
            core_version_heatmap=${red_text}
            CORE_VERSION="?"
        else
            GetPADDValue version.core.local.hash CORE_HASH
            GetPADDValue version.core.remote.hash GITHUB_CORE_HASH

            if [ "${CORE_HASH}" = "${GITHUB_CORE_HASH}" ]; then
                # up-to-date
                core_version_heatmap=${green_text}
            else
                # out-of-date
                out_of_date_flag="true"
                core_version_heatmap=${red_text}
            fi

            ShortenBranch "${CORE_BRANCH}" CORE_VERSION
        fi
    fi

    # Gather web version information...
    GetPADDValue version.web.local.version WEB_VERSION

    if [ "${WEB_VERSION}" != "null" ]; then
        GetPADDValue version.web.local.branch WEB_BRANCH

        if [ "${WEB_BRANCH}" = "master" ]; then
            CleanVersion "${WEB_VERSION}" WEB_VERSION
            GetPADDValue version.web.remote.version GITHUB_WEB_VERSION
            CompareMasterVersion "${WEB_VERSION}" "${GITHUB_WEB_VERSION}" web_version_heatmap
        else
            # Custom branch
            if [ -z "${WEB_BRANCH}"  ]; then
                # Branch name is empty, something went wrong
                web_version_heatmap=${red_text}
                WEB_VERSION="?"
            else
                GetPADDValue version.web.local.hash WEB_HASH
                GetPADDValue version.web.remote.hash GITHUB_WEB_HASH

                if [ "${WEB_HASH}" = "${GITHUB_WEB_HASH}" ]; then
                    # up-to-date
                    web_version_heatmap=${green_text}
                else
                    # out-of-date
                    out_of_date_flag="true"
                    web_version_heatmap=${red_text}
                fi

                ShortenBranch "${WEB_BRANCH}" WEB_VERSION
            fi
        fi
    else
        # Web interface not installed
        WEB_VERSION="N/A"
        web_version_heatmap=${yellow_text}
    fi

    # Gather FTL version information...
    GetPADDValue version.ftl.local.branch FTL_BRANCH

    if [ "${FTL_BRANCH}" = "master" ]; then
        GetPADDValue version.ftl.local.version FTL_VERSION_raw
        CleanVersion "${FTL_VERSION_raw}" FTL_VERSION
        GetPADDValue version.ftl.remote.version GITHUB_FTL_VERSION
        CompareMasterVersion "${FTL_VERSION}" "${GITHUB_FTL_VERSION}" ftl_version_heatmap
    else
        # Custom branch
        if [ -z "${FTL_BRANCH}"  ]; then
            # Branch name is empty, something went wrong
            ftl_version_heatmap=${red_text}
            FTL_VERSION="?"
        else
            GetPADDValue version.ftl.local.hash FTL_HASH
            GetPADDValue version.ftl.remote.hash GITHUB_FTL_HASH

            if [ "${FTL_HASH}" = "${GITHUB_FTL_HASH}" ]; then
                # up-to-date
                ftl_version_heatmap=${green_text}
            else
                # out-of-date
                out_of_date_flag="true"
                ftl_version_heatmap=${red_text}
            fi

            ShortenBranch "${FTL_BRANCH}" FTL_VERSION
        fi
    fi

}

GetPADDInformation() {
    local release_json padd_version_latest_converted padd_version_converted

    # PADD version information...
    release_json="$(curl --connect-timeout 5 --max-time 20 --silent https://api.github.com/repos/pi-hole/PADD/releases/latest)"
    padd_version_latest=$(jq -r '.tag_name // empty' 2>/dev/null <<EOF
${release_json}
EOF
)
    # is PADD up-to-date?
    padd_out_of_date_flag="false"
    if [ -z "${padd_version_latest}" ]; then
        padd_version_heatmap=${yellow_text}
    else
        padd_version_latest_converted="$(VersionConverter "${padd_version_latest}")"
        padd_version_converted=$(VersionConverter "${padd_version}")

        if [ "${padd_version_converted}" -lt "${padd_version_latest_converted}" ]; then
            padd_out_of_date_flag="true"
            padd_version_heatmap=${red_text}
        else
            # local and remote PADD version match or local is newer
            padd_version_heatmap=${green_text}
        fi
    fi
}

GenerateSizeDependentOutput() {
    latest_blocked=""
    top_blocked=""
    top_domain=""
    top_client=""
    sys_model_short=""
    

    if [ "$1" = "pico" ] || [ "$1" = "nano" ]; then
        BarGenerator "${ads_percentage_today}" 9 "color"
        ads_blocked_bar=${bar_out}

    elif [ "$1" = "micro" ]; then
        BarGenerator "${ads_percentage_today}" 10 "color"
        ads_blocked_bar=${bar_out}

    elif [ "$1" = "mini" ]; then
        BarGenerator "${ads_percentage_today}" 20 "color"
        ads_blocked_bar=${bar_out}

        truncateString "${latest_blocked_raw}" 29 latest_blocked
        truncateString "${top_blocked_raw}" 29 top_blocked

    elif [ "$1" = "tiny" ]; then
        BarGenerator "${ads_percentage_today}" 30 "color"
        ads_blocked_bar=${bar_out}

        truncateString "${latest_blocked_raw}" 41 latest_blocked
        truncateString "${top_blocked_raw}" 41 top_blocked
        truncateString "${top_domain_raw}" 41 top_domain
        truncateString "${top_client_raw}" 41 top_client

    elif [ "$1" = "regular" ] || [ "$1" = "slim" ]; then
        BarGenerator "${ads_percentage_today}" 40 "color"
        ads_blocked_bar=${bar_out}

        truncateString "${latest_blocked_raw}" 48 latest_blocked
        truncateString "${top_blocked_raw}" 48 top_blocked
        truncateString "${top_domain_raw}" 48 top_domain
        truncateString "${top_client_raw}" 48 top_client

        if [ "${temp_unicode}" = true ]; then
            temp_padding=21
        else
            temp_padding=20
        fi

    elif [ "$1" = "mega" ]; then
        BarGenerator "${ads_percentage_today}" 30 "color"
        ads_blocked_bar=${bar_out}

        truncateString "${latest_blocked_raw}" 68 latest_blocked
        truncateString "${top_blocked_raw}" 68 top_blocked
        truncateString "${top_domain_raw}" 68 top_domain
        truncateString "${top_client_raw}" 68 top_client
        truncateString "${sys_model}" 20 sys_model_short

        if [ "${temp_unicode}" = true ]; then
            temp_padding=10
        else
            temp_padding=9
        fi

    fi

    # System uptime
    convertUptime "${system_uptime_raw:-0}"
    system_uptime="${uptime_out}"
    if [ "$1" = "pico" ] || [ "$1" = "nano" ] || [ "$1" = "micro" ]; then
        system_uptime="${system_uptime%,*}"
    fi

    # Bar generations
    if [ "$1" = "mini" ]; then
        BarGenerator "${cpu_percent}" 20
        cpu_bar=${bar_out}
        BarGenerator "${memory_percent}" 20
        memory_bar=${bar_out}
    elif [ "$1" = "tiny" ]; then
        BarGenerator "${cpu_percent}" 7
        cpu_bar=${bar_out}
        BarGenerator "${memory_percent}" 7
        memory_bar=${bar_out}
    else
        BarGenerator "${cpu_percent}" 10
        cpu_bar=${bar_out}
        BarGenerator "${memory_percent}" 10
        memory_bar=${bar_out}
        if [ "$1" = "mega" ]; then
            BarGenerator "${swap_percent}" 10
            swap_bar=${bar_out}
        fi
    fi
}

SetStatusMessage() {
    # Depending on which flags are set, the status field shows one of 6 messages
    # (from highest to lowest priority):
    #   - System is hot
    #   - FTLDNS service is not running / unreachable
    #   - Pi-hole's DNS server is off (FTL running, but not providing DNS)
    #   - Pi-hole blocking disabled
    #   - Updates are available
    #   - Everything is fine


    if [ "${hot_flag}" = true ]; then
        # Check if CPU temperature is high
        pico_status="${pico_status_hot}"
        mini_status="${mini_status_hot} ${blinking_text}${red_text}${temperature}${reset_text}"
        tiny_status="${tiny_status_hot} ${blinking_text}${red_text}${temperature}${reset_text}"
        full_status="${full_status_hot} ${blinking_text}${red_text}${temperature}${reset_text}"
        mega_status="${mega_status_hot} ${blinking_text}${red_text}${temperature}${reset_text}"

    elif [ "${connection_down_flag}" = true ]; then
        # Check if FTL is down
        pico_status=${pico_status_ftl_down}
        mini_status=${mini_status_ftl_down}
        tiny_status=${tiny_status_ftl_down}
        full_status=${full_status_ftl_down}
        mega_status=${mega_status_ftl_down}

    elif [ "${dns_down_flag}" = true ]; then
        # Check if DNS is down
        pico_status=${pico_status_dns_down}
        mini_status=${mini_status_dns_down}
        tiny_status=${tiny_status_dns_down}
        full_status=${full_status_dns_down}
        mega_status=${mega_status_dns_down}

    elif [ "${blocking_enabled}" = "disabled" ]; then
        # Check if blocking status is disabled
        pico_status=${pico_status_off}
        mini_status=${mini_status_off}
        tiny_status=${tiny_status_off}
        full_status=${full_status_off}
        mega_status=${mega_status_off}

    elif [ "${out_of_date_flag}" = "true" ] || [ "${padd_out_of_date_flag}" = "true" ]; then
        # Check if one of the components of Pi-hole (or PADD itself) is out of date
        pico_status=${pico_status_update}
        mini_status=${mini_status_update}
        tiny_status=${tiny_status_update}
        full_status=${full_status_update}
        mega_status=${mega_status_update}

    elif [ "${blocking_enabled}" = "enabled" ]; then
        # if we reach this point and blocking is enabled, everything is fine
        pico_status=${pico_status_ok}
        mini_status=${mini_status_ok}
        tiny_status=${tiny_status_ok}
        full_status=${full_status_ok}
        mega_status=${mega_status_ok}
    fi
}

############################################# PRINTERS #############################################

PrintLogo() {
    # Screen size checks
    if [ "$1" = "pico" ]; then
        moveXOffset; printf "%s${clear_line}\n" "p${padd_text}"
    elif [ "$1" = "nano" ]; then
        moveXOffset; printf "%s${clear_line}\n" "n${padd_text}"
    elif [ "$1" = "micro" ]; then
        moveXOffset; printf "%s${clear_line}\n\n" "µ${padd_text}"
    elif [ "$1" = "mini" ]; then
        moveXOffset; printf "%s${clear_line}\n" "${padd_text}${dim_text}mini${reset_text} Pi-hole® Ad Detection Display"
        moveXOffset; printf "%s${clear_line}\n" "         A client for Pi-hole®"
    else
        moveXOffset; printf "%b" "${padd_logo_1}\n"
        moveXOffset; printf "%b" "${padd_logo_2}Pi-hole® Ad Detection Display\n"
        moveXOffset; printf "%b" "${padd_logo_3}A client for Pi-hole\n\n"
    fi
}

PrintDashboard() {
    local version_info
    if [ "${DOCKER_VERSION}" != "null" ]; then
        version_info="Docker ${docker_version_heatmap}${DOCKER_VERSION}${reset_text}"
    else
        version_info="Pi-hole® ${core_version_heatmap}${CORE_VERSION}${reset_text}, Web ${web_version_heatmap}${WEB_VERSION}${reset_text}, FTL ${ftl_version_heatmap}${FTL_VERSION}${reset_text}"
    fi
    # Move cursor to (0,0).
    printf '\033[H'

    # adds the y-offset
    moveYOffset

    if [ "$1" = "ants" ]; then
        # Terminal resized below 20x10: show warning without exiting so resizing back recovers
        printf "%b" "${check_box_bad}\nThis is\ntoo small!\nPADD isn't\nfor ants!\n"
    elif [ "$1" = "pico" ]; then
        # pico is a screen at least 20x10 (columns x lines)
        moveXOffset; printf "%s${clear_line}\n" "p${padd_text} ${pico_status}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}PI-HOLE ============${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" " [${ads_blocked_bar}] ${ads_percentage_today}%"
        moveXOffset; printf "%s${clear_line}\n" " ${ads_blocked_today} / ${dns_queries_today}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}NETWORK ============${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" " Hst: ${pi_hostname}"
        moveXOffset; printf "%s${clear_line}\n" " IP:  ${pi_ip4_addr}"
        moveXOffset; printf "%s${clear_line}\n" " IPv6 ${ipv6_check_box} DHCP ${dhcp_check_box}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}CPU ================${reset_text}"
        moveXOffset; printf "%s${clear_line}" " [${cpu_percent_heatmap}${cpu_bar}${reset_text}] ${cpu_percent}%"
    elif [ "$1" = "nano" ]; then
        # nano is a screen at least 24x12 (columns x lines)
        moveXOffset; printf "%s${clear_line}\n" "n${padd_text} ${mini_status}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}PI-HOLE ================${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" " DNS: ${dns_check_box}      FTL: ${ftl_check_box}"
        moveXOffset; printf "%s${clear_line}\n" " Blk: [${ads_blocked_bar}] ${ads_percentage_today}%"
        moveXOffset; printf "%s${clear_line}\n" " Blk: ${ads_blocked_today} / ${dns_queries_today}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}NETWORK ================${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" " Host: ${pi_hostname}"
        moveXOffset; printf "%s${clear_line}\n" " IP:   ${pi_ip4_addr}"
        moveXOffset; printf "%s${clear_line}\n" " IPv6: ${ipv6_check_box}    DHCP: ${dhcp_check_box}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}SYSTEM =================${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" " Up:  ${system_uptime}"
        moveXOffset; printf "%s${clear_line}"  " CPU: [${cpu_percent_heatmap}${cpu_bar}${reset_text}] ${cpu_percent}%"
    elif [ "$1" = "micro" ]; then
        # micro is a screen at least 30x16 (columns x lines)
        moveXOffset; printf "%s${clear_line}\n" "µ${padd_text}     ${mini_status}"
        moveXOffset; printf "%s${clear_line}\n" ""
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}PI-HOLE ======================${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" " DNS:  ${dns_check_box}        FTL:  ${ftl_check_box}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}STATS ========================${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" " Blckng:  ${domains_being_blocked} domains"
        moveXOffset; printf "%s${clear_line}\n" " Piholed: [${ads_blocked_bar}] ${ads_percentage_today}%"
        moveXOffset; printf "%s${clear_line}\n" " Piholed: ${ads_blocked_today} / ${dns_queries_today}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}NETWORK ======================${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" " Host:    ${full_hostname}"
        moveXOffset; printf "%s${clear_line}\n" " IP:      ${pi_ip4_addr}"
        moveXOffset; printf "%s${clear_line}\n" " IPv6: ${ipv6_check_box}       DHCP:  ${dhcp_check_box}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}SYSTEM =======================${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" " Uptime:  ${system_uptime}"
        moveXOffset; printf "%s${clear_line}\n" " Load:    [${cpu_percent_heatmap}${cpu_bar}${reset_text}] ${cpu_percent}%"
        moveXOffset; printf "%s${clear_line}" " Memory:  [${memory_heatmap}${memory_bar}${reset_text}] ${memory_percent}%"
    elif [ "$1" = "mini" ]; then
        # mini is a screen at least 40x18 (columns x lines)
        moveXOffset; printf "%s${clear_line}\n" "${padd_text}${dim_text}mini${reset_text}  ${mini_status}"
        moveXOffset; printf "%s${clear_line}\n" ""
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}PI-HOLE ================================${reset_text}"
        moveXOffset; printf " %-9s${dns_heatmap}%-10s${reset_text} %-5s${ftl_heatmap}%-10s${reset_text}${clear_line}\n" "DNS:" "${dns_status}" "FTL:" "${ftl_status}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}STATS ==================================${reset_text}"
        moveXOffset; printf " %-9s%-29s${clear_line}\n" "Blckng:" "${domains_being_blocked} domains"
        moveXOffset; printf " %-9s[%-20s] %-5s${clear_line}\n" "Piholed:" "${ads_blocked_bar}" "${ads_percentage_today}%"
        moveXOffset; printf " %-9s%-29s${clear_line}\n" "Piholed:" "${ads_blocked_today} out of ${dns_queries_today}"
        moveXOffset; printf " %-9s%-29s${clear_line}\n" "Latest:" "${latest_blocked}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}NETWORK ================================${reset_text}"
        moveXOffset; printf " %-9s%-16s%-5s%-9s${clear_line}\n" "Host:" "${full_hostname}" "DNS:" "${dns_information}"
        moveXOffset; printf " %-9s%s${clear_line}\n" "IP:" "${pi_ip4_addr} (${iface_name})"
        moveXOffset; printf " %-9s${ipv6_heatmap}%-10s${reset_text} %-8s${dhcp_heatmap}%-10s${reset_text}${clear_line}\n" "IPv6:" "${ipv6_status}" "DHCP:" "${dhcp_status}"

        moveXOffset; printf " %-9s%-4s%-12s%-4s%-5s${clear_line}\n" "Traffic:" "TX:" "${tx_bytes}" "RX:" "${rx_bytes}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}SYSTEM =================================${reset_text}"
        moveXOffset; printf " %-9s%-29s${clear_line}\n" "Uptime:" "${system_uptime}"
        moveXOffset; printf "%s${clear_line}\n" " Load:    [${cpu_percent_heatmap}${cpu_bar}${reset_text}] ${cpu_percent}%"
        moveXOffset; printf "%s${clear_line}" " Memory:  [${memory_heatmap}${memory_bar}${reset_text}] ${memory_percent}%"
    elif [ "$1" = "tiny" ]; then
         # tiny is a screen at least 53x20 (columns x lines)
        moveXOffset; printf "%s${clear_line}\n" "${padd_text}${dim_text}tiny${reset_text}   ${version_info}${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" "           PADD ${padd_version_heatmap}${padd_version}${reset_text} ${tiny_status}${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}PI-HOLE =============================================${reset_text}"
        moveXOffset; printf " %-10s${dns_heatmap}%-16s${reset_text} %-8s${ftl_heatmap}%-10s${reset_text}${clear_line}\n" "DNS:" "${dns_status}" "FTL:" "${ftl_status}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}STATS ===============================================${reset_text}"
        moveXOffset; printf " %-10s%-29s${clear_line}\n" "Blocking:" "${domains_being_blocked} domains"
        moveXOffset; printf " %-10s[%-30s] %-5s${clear_line}\n" "Pi-holed:" "${ads_blocked_bar}" "${ads_percentage_today}%"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Pi-holed:" "${ads_blocked_today} out of ${dns_queries_today}"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Latest:" "${latest_blocked}"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Top Ad:" "${top_blocked}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}NETWORK =============================================${reset_text}"
        moveXOffset; printf " %-10s%-16s %-8s%-16s${clear_line}\n" "Hostname:" "${full_hostname}" "IP:  " "${pi_ip4_addr}"
        moveXOffset; printf " %-10s%-16s %-4s%-7s %-4s%-5s${clear_line}\n" "Interfce:" "${iface_name}" "TX:" "${tx_bytes}" "RX:" "${rx_bytes}"
        moveXOffset; printf " %-10s%-16s %-8s${dnssec_heatmap}%-16s${reset_text}${clear_line}\n" "DNS:" "${dns_information}" "DNSSEC:" "${dnssec_status}"
        moveXOffset; printf " %-10s%s${clear_line}\n" "IPv6:" "${pi_ip6_addr}"
        moveXOffset; printf " %-10s%-5s %-4s${dhcp_range_heatmap}%-33s${reset_text}${clear_line}\n" "DHCP:" "${dhcp_check_box}" "Rng" "${dhcp_range}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}SYSTEM ==============================================${reset_text}"
        moveXOffset; printf " %-10s%-29s${clear_line}\n" "Uptime:" "${system_uptime}"
        moveXOffset; printf " %-10s${temp_heatmap}%-17s${reset_text} %-8s${cpu_load_1_heatmap}%-4s${reset_text}, ${cpu_load_5_heatmap}%-4s${reset_text}, ${cpu_load_15_heatmap}%-4s${reset_text}${clear_line}\n" "CPU Temp:" "${temperature}" "Load:" "${cpu_load_1}" "${cpu_load_5}" "${cpu_load_15}"
        moveXOffset; printf " %-10s[${memory_heatmap}%-7s${reset_text}] %-6s %-8s[${cpu_load_1_heatmap}%-7s${reset_text}] %-5s${clear_line}" "Memory:" "${memory_bar}" "${memory_percent}%" "CPU:" "${cpu_bar}" "${cpu_percent}%"
    elif [ "$1" = "regular" ] || [ "$1" = "slim" ]; then
        # slim is a screen with at least 60 columns and exactly 21 lines
        # regular is a screen at least 60x22 (columns x lines)
        if [ "$1" = "slim" ]; then
           moveXOffset; printf "%s${clear_line}\n" "${padd_text}${dim_text}slim${reset_text}   ${version_info}${reset_text}"
           moveXOffset; printf "%s${clear_line}\n" "           PADD ${padd_version_heatmap}${padd_version}${reset_text}   ${full_status}${reset_text}"
           moveXOffset; printf "%s${clear_line}\n" ""
        else
            moveXOffset; printf "%s${clear_line}\n" "${padd_logo_1}"
            moveXOffset; printf "%s${clear_line}\n" "${padd_logo_2}${version_info}${reset_text}"
            moveXOffset; printf "%s${clear_line}\n" "${padd_logo_3}PADD ${padd_version_heatmap}${padd_version}${reset_text}   ${full_status}${reset_text}"
            moveXOffset; printf "%s${clear_line}\n" ""
        fi
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}PI-HOLE ====================================================${reset_text}"
        moveXOffset; printf " %-10s${dns_heatmap}%-19s${reset_text} %-10s${ftl_heatmap}%-19s${reset_text}${clear_line}\n" "DNS:" "${dns_status}" "FTL:" "${ftl_status}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}STATS ======================================================${reset_text}"
        moveXOffset; printf " %-10s%-49s${clear_line}\n" "Blocking:" "${domains_being_blocked} domains"
        moveXOffset; printf " %-10s[%-40s] %-5s${clear_line}\n" "Pi-holed:" "${ads_blocked_bar}" "${ads_percentage_today}%"
        moveXOffset; printf " %-10s%-49s${clear_line}\n" "Pi-holed:" "${ads_blocked_today} out of ${dns_queries_today} queries"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Latest:" "${latest_blocked}"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Top Ad:" "${top_blocked}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}NETWORK ====================================================${reset_text}"
        moveXOffset; printf " %-10s%-15s %-4s%-17s${clear_line}\n" "Hostname:" "${full_hostname}" "IP:" "${pi_ip4_addr}"
        moveXOffset; printf " %-10s%-15s %-4s%-17s%-4s%s${clear_line}\n" "Interfce:" "${iface_name}" "TX:" "${tx_bytes}" "RX:" "${rx_bytes}"
        moveXOffset; printf " %-10s%s${clear_line}\n" "IPv6:" "${pi_ip6_addr}"
        moveXOffset; printf " %-10s%-15s %-10s${dnssec_heatmap}%-19s${reset_text}${clear_line}\n" "DNS:" "${dns_information}" "DNSSEC:" "${dnssec_status}"
        moveXOffset; printf " %-10s%-16s%-6s${dhcp_range_heatmap}%-36s${reset_text}${clear_line}\n" "DHCP:" "${dhcp_check_box}" "Range" "${dhcp_range}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}SYSTEM =====================================================${reset_text}"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Uptime:" "${system_uptime}"
        moveXOffset; printf " %-10s${temp_heatmap}%-""${temp_padding}""s${reset_text}%-10s${cpu_load_1_heatmap}%-4s${reset_text}, ${cpu_load_5_heatmap}%-4s${reset_text}, ${cpu_load_15_heatmap}%-4s${reset_text}${clear_line}\n" "CPU Temp:" "${temperature}" "CPU Use:" "${cpu_load_1}" "${cpu_load_5}" "${cpu_load_15}"
        moveXOffset; printf " %-10s[${memory_heatmap}%-10s${reset_text}] %-6s %-10s[${cpu_load_1_heatmap}%-10s${reset_text}] %-5s${clear_line}" "Memory:" "${memory_bar}" "${memory_percent}%" "CPU %:" "${cpu_bar}" "${cpu_percent}%"
    else # $1 = "mega"
         # mega is a screen with at least 80 columns and 26 lines
        moveXOffset; printf "%s${clear_line}\n" "${padd_logo_1}"
        moveXOffset; printf "%s${clear_line}\n" "${padd_logo_2}   ${version_info}, PADD ${padd_version_heatmap}${padd_version}${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" "${padd_logo_3}   ${dns_check_box} DNS   ${ftl_check_box} FTL   ${mega_status}${reset_text}"
        moveXOffset; printf "%s${clear_line}\n" ""
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}STATS ==========================================================================${reset_text}"
        moveXOffset; printf " %-10s%-19s %-10s[%-40s] %-5s${clear_line}\n" "Blocking:" "${domains_being_blocked} domains" "Piholed:" "${ads_blocked_bar}" "${ads_percentage_today}%"
        moveXOffset; printf " %-10s%-30s%-29s${clear_line}\n" "Clients:" "${clients}" " ${ads_blocked_today} out of ${dns_queries_today} queries"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Latest:" "${latest_blocked}"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Top Ad:" "${top_blocked}"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Top Dmn:" "${top_domain}"
        moveXOffset; printf " %-10s%-39s${clear_line}\n" "Top Clnt:" "${top_client}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}FTL ============================================================================${reset_text}"
        moveXOffset; printf " %-10s%-9s %-10s${ftl_cpu_heatmap}%-9s${reset_text} %-10s${ftl_mem_heatmap}%-9s${reset_text} %-10s%-9s${clear_line}\n" "PID:" "${ftlPID}" "CPU Use:" "${ftl_cpu}" "Mem. Use:" "${ftl_mem_percentage}" "${dns_query_rate_label}" "${dns_queries_frequency}"
        moveXOffset; printf " %-10s%-69s${clear_line}\n" "DNSCache:" "${cache_inserts} insertions, ${cache_evictions} deletions, ${cache_size} total entries"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}NETWORK ========================================================================${reset_text}"
        moveXOffset; printf " %-10s%-15s %-10s%-19s${clear_line}\n" "Hostname:" "${full_hostname}" "Gateway:" "${gw_v4_addr}"
        moveXOffset; printf " %-10s%-15s %-4s%-9s %-4s%-9s${clear_line}\n" "Interfce:" "${iface_name}" "TX:" "${tx_bytes}" "RX:" "${rx_bytes}"
        moveXOffset; printf " %-6s%-19s %-10s%-29s${clear_line}\n" "IPv4:" "${pi_ip4_addr}" "IPv6:" "${pi_ip6_addr}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}DNS ===========================================DHCP=====================${reset_text}"
        moveXOffset; printf " %-50s%-6s${dhcp_heatmap}%-10s${reset_text}${clear_line}\n" "Servers: ${dns_information}  Port: ${dns_port_display}" "DHCP:" "${dhcp_status}"
        moveXOffset; printf " %-50s%-10s${dhcp_ipv6_heatmap}%-6s${reset_text}${clear_line}\n" "DNSSEC: ${dnssec_status}  Domain: ${dns_domain_display}" "IPv6 Spt:" "${dhcp_ipv6_status}"
        moveXOffset; printf " %-50s%-6s${dhcp_range_heatmap}%-22s${reset_text}${clear_line}\n" "CdFwding: ${conditional_forwarding_status}" "Range" "${dhcp_range}"
        moveXOffset; printf "%s${clear_line}\n" "${bold_text}SYSTEM =========================================================================${reset_text}"
        moveXOffset; printf " %-10s%-20s %-5s%-13s %-10s[${swap_heatmap}%-10s${reset_text}] %-6s${clear_line}\n" "Device:" "${sys_model_short}" "RAM:" "${memory_used_total}" "Memory:" "${memory_bar}" "${memory_percent}%"
        moveXOffset; printf " %-10s%-39s %-10s[${memory_heatmap}%-10s${reset_text}] %-6s${clear_line}\n" "Uptime:" "${system_uptime}" "Swap:" "${swap_bar}" "${swap_percent}%"
        moveXOffset; printf " %-10s${temp_heatmap}%-""${temp_padding}""s${reset_text} %-10s${cpu_load_1_heatmap}%-4s${reset_text}, ${cpu_load_5_heatmap}%-4s${reset_text}, ${cpu_load_15_heatmap}%-7s${reset_text} %-10s[${cpu_percent_heatmap}%-10s${reset_text}] %-6s${clear_line}" "CPU Temp:" "${temperature}" "CPU Load:" "${cpu_load_1}" "${cpu_load_5}" "${cpu_load_15}" "CPU %:" "${cpu_bar}" "${cpu_percent}%"
    fi

    # Clear to end of screen (below the drawn dashboard)
    # https://vt100.net/docs/vt510-rm/ED.html
    printf '\033[0J'
}

############################################# HELPERS ##############################################

# Sets global `heat_out` to a color based on a percentage (1 arg) or ratio (2 args)
# Uses a global output variable instead of stdout to avoid subshell forks.
HeatmapGenerator () {
    local load out
    # if one number is provided, just use that percentage to figure out the colors
    if [ -z "${2}" ]; then
        load=$(printf "%.0f" "${1}")
    # guard against division by zero if core_count is 0
    elif [ "${2}" = "0" ]; then
        load=0
    # if two numbers are provided, do some math to make a percentage to figure out the colors
    else
        load=$(awk -v a="${1}" -v b="${2}" 'BEGIN { printf "%.0f\n", (a / b) * 100 }')
    fi

    # Color logic
    #  |<-                 green                  ->| yellow |  red ->
    #  0  5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100
    if [ "${load}" -lt 75 ]; then
        out=${green_text}
    elif [ "${load}" -lt 90 ]; then
        out=${yellow_text}
    else
        out=${red_text}
    fi

    heat_out="${out}"
}

# Sets global `bar_out` to a progress bar string without a subshell capture.
# $1: percentage filled
# $2: max length of the bar
# $3: colored flag, if "color" backfill with color
BarGenerator() {
    local barNumber frontFill backFill i backfillNumber out
    # number of filled in cells in the bar
    barNumber=$(awk -v pct="${1}" -v width="${2}" 'BEGIN { printf "%.f\n", (pct / 100) * width }')

    # Build frontFill using a native loop instead of using seq
    frontFill=""
    i=0
    while [ "${i}" -lt "${barNumber}" ]; do
        frontFill="${frontFill}■"
        i=$((i + 1))
    done

    # remaining "unfilled" cells in the bar
    backfillNumber=$(($2-barNumber))

    # if the filled in cells is less than the max length of the bar, fill it
    if [ "${barNumber}" -lt "${2}" ]; then
        # if the bar should be colored
        if [ "${3}" = "color" ]; then
            # fill the rest in color
            backFill=""
            i=0
            while [ "${i}" -lt "${backfillNumber}" ]; do
                backFill="${backFill}■"
                i=$((i + 1))
            done
            out="${red_text}${frontFill}${green_text}${backFill}${reset_text}"
        else
            # fill the rest with "space" ("·")
            backFill=""
            i=0
            while [ "${i}" -lt "${backfillNumber}" ]; do
                backFill="${backFill}·"
                i=$((i + 1))
            done
            out="${frontFill}${reset_text}${backFill}"
        fi
    else
        # fill it all the way
        out=""
        i=0
        while [ "${i}" -lt "$2" ]; do
            out="${out}■"
            i=$((i + 1))
        done
        out="${out}${reset_text}"
    fi

    bar_out="${out}"
}

# Checks the size of the screen and sets `padd_size`, `xOffset`, and `yOffset`
SizeChecker(){
    local console_width console_height width height xMaxOffset yMaxOffset
    # Adding a tiny delay here to give the kernel a bit of time to
    # report new sizes correctly after a terminal resize;
    # this reduces flickering of GenerateSizeDependentOutput() items
    sleep 0.1
    console_width=$(tput cols)
    console_height=$(tput lines)

    # Mega
    if [ "${console_width}" -ge "80" ] && [ "${console_height}" -ge "26" ]; then
        padd_size="mega"
        width=80
        height=26
    # Below Mega. Gives you Regular.
    elif [ "${console_width}" -ge "60" ] && [ "${console_height}" -ge "22" ]; then
        padd_size="regular"
        width=60
        height=22
    # Below Regular. Gives you Slim.
    elif [ "${console_width}" -ge "60" ] && [ "${console_height}" -ge "21" ]; then
        padd_size="slim"
        width=60
        height=21
    # Below Slim. Gives you Tiny.
    elif [ "${console_width}" -ge "53" ] && [ "${console_height}" -ge "20" ]; then
        padd_size="tiny"
        width=53
        height=20
    # Below Tiny. Gives you Mini.
    elif [ "${console_width}" -ge "40" ] && [ "${console_height}" -ge "18" ]; then
        padd_size="mini"
        width=40
        height=18
    # Below Mini. Gives you Micro.
    elif [ "${console_width}" -ge "30" ] && [ "${console_height}" -ge "16" ]; then
        padd_size="micro"
        width=30
        height=16
    # Below Micro, Gives you Nano.
    elif [ "${console_width}" -ge "24" ] && [ "${console_height}" -ge "12" ]; then
        padd_size="nano"
        width=24
        height=12
    # Below Nano. Gives you Pico.
    elif [ "${console_width}" -ge "20" ] && [ "${console_height}" -ge "10" ]; then
        padd_size="pico"
        width=20
        height=10
    # Below Pico. Gives you nothing...
    else
        padd_size="ants"
        xOffset=0
        yOffset=0
        return
    fi

    # Center the output (default position)
    xOffset="$(( (console_width - width) / 2 ))"
    yOffset="$(( (console_height - height) / 2 ))"

    # If the user sets an offset option, use it.
    if [ -n "${xOffOrig}" ]; then
        xOffset=${xOffOrig}

        # Limit the offset to avoid breaks
        xMaxOffset=$((console_width - width))
        if [ "${xMaxOffset}" -lt 0 ]; then
            xMaxOffset=0
        fi
        if [ "${xOffset}" -gt "${xMaxOffset}" ]; then
            xOffset="${xMaxOffset}"
        fi
    fi
    if [ -n "${yOffOrig}" ]; then
        yOffset=${yOffOrig}

        # Limit the offset to avoid breaks
        yMaxOffset=$((console_height - height))
        if [ "${yMaxOffset}" -lt 0 ]; then
            yMaxOffset=0
        fi
        if [ "${yOffset}" -gt "${yMaxOffset}" ]; then
            yOffset="${yMaxOffset}"
        fi
    fi
}

# Converts a version string (e.g. v3.7.1 -> 3007001000) for numeric comparison
# Passes the value via awk -v in BEGIN to avoid a pipe
# credits https://apple.stackexchange.com/a/123408
VersionConverter() {
    awk -v v="$*" 'BEGIN { gsub(/[[:alpha:]]/, "", v); split(v, a, "."); printf("%d%03d%03d%03d\n", a[1],a[2],a[3],a[4]); }'
}

moveYOffset(){
    # Moves the cursor yOffset lines down (https://vt100.net/docs/vt510-rm/CUD.html)
    # Guarded because CSI 0 B is treated as 1; defaults to 0 for calls before SizeChecker()
    if [ "${yOffset:-0}" -gt 0 ]; then
        printf '\033[%sB' "${yOffset}"
    fi
}

moveXOffset(){
    # Moves the cursor xOffset columns right (https://vt100.net/docs/vt510-rm/CUF.html)
    # Guarded because CSI 0 C is treated as 1; defaults to 0 for calls before SizeChecker()
    if [ "${xOffset:-0}" -gt 0 ]; then
        printf '\033[%sC' "${xOffset}"
    fi
}

# Remove undesired strings from sys_model variable - used in GetSystemInformation() function
filterModel() {
    local FILTERLIST
    FILTERLIST="To be filled by O.E.M.|Not Applicable|System Product Name|System Version|Undefined|Default string|Not Specified|Type1ProductConfigId|INVALID|All Series"

    # Description:
    #    `-v`                 : pass $FILTERLIST and $1 directly into awk (no pipe)
    #    `BEGIN`              : build a case-insensitive regex from `list` by turning every letter into [xX].
    #                           Done by hand because mawk (Debian's default awk) has no IGNORECASE
    #    `gsub()`             : replace all list items (ignoring case) with an empty string, deleting them
    #    `$1 = $1; print`     : remove all extra spaces, then print the result
    awk -v list="${FILTERLIST}" -v model="$1" '
    BEGIN {
        re = ""
        for (i = 1; i <= length(list); i++) {
            c = substr(list, i, 1)
            if (c ~ /[A-Za-z]/) re = re "[" tolower(c) toupper(c) "]"
            else re = re c
        }
        $0 = model
        gsub(re, "")
        $1 = $1
        print
    }'
}

# Truncates a string to max_length (appending '...') and assigns it to <variable>
truncateString() {
    # Usage: truncateString <string> <max_length> <variable>
    # Validate target variable name before eval
    case "${3}" in ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;; esac
    local length shorted drop prefix
    length=${#1}
    shorted=$((${2} - 3))
    prefix="${1}"
    if [ "${length}" -gt "${2}" ]; then
        # Trim trailing characters in-process via POSIX expansion (no printf/cut subshell)
        drop=$((length - shorted))
        while [ "${drop}" -gt 0 ]; do
            prefix="${prefix%?}"
            drop=$((drop - 1))
        done
        prefix="${prefix}..."
    fi

    eval "${3}=\${prefix}"
}

# Converts seconds to days, hours, minutes
# https://unix.stackexchange.com/a/338844
convertUptime() {
    # Sets uptime_out, e.g. "3 days, 04 hours, 05 minutes", without a subshell
    local secs D H M
    secs="${1:-0}"
    case "${secs}" in
        ''|*[!0-9]*) secs=0 ;;
    esac
    D=$((secs/60/60/24))
    H=$((secs/60/60%24))
    M=$((secs/60%60))
    if [ "${H}" -lt 10 ]; then H="0${H}"; fi
    if [ "${M}" -lt 10 ]; then M="0${M}"; fi
    uptime_out="${D} days, ${H} hours, ${M} minutes"
}

secretRead() {
    local key charcount
    # POSIX compliant function to read user-input and
    # mask every character entered by (*)
    #
    # This is challenging, because in POSIX, `read` does not support
    # `-s` option (suppressing the input) or
    # `-n` option (reading n chars)


    # This workaround changes the terminal characteristics to not echo input and later resets this option
    # credits https://stackoverflow.com/a/4316765
    # showing asterisk instead of password
    # https://stackoverflow.com/a/24600839
    # https://unix.stackexchange.com/a/464963

    stty -echo # do not echo user input
    stty -icanon min 1 time 0 # disable canonical mode https://man7.org/linux/man-pages/man3/termios.3.html

    unset password
    unset key
    unset charcount
    charcount=0
    while key=$(dd ibs=1 count=1 2>/dev/null); do #read one byte of input
        # If key is empty (Enter key pressed), accept password and break loop
        if [ -z "${key}" ] ; then
            break
        fi
        if [ "${key}" = "$(printf '\177')" ] ; then
            # Backspace
            if [ ${charcount} -gt 0 ] ; then
                charcount=$((charcount-1))
                printf '\b \b'
                password="${password%?}"
            fi
        else
            # any other character
            charcount=$((charcount+1))
            printf '*'
            password="${password}${key}"
        fi
    done

    # restore original terminal settings
    stty "${stty_orig}"
}

check_dependencies() {
    local hasDeps=true
    # Check for required dependencies
    if ! command -v curl >/dev/null 2>&1; then
        printf "%b" "${check_box_bad} Error!\n    'curl' is missing but required.\n"
        hasDeps=false
    fi

    if ! command -v jq >/dev/null 2>&1; then
        printf "%b" "${check_box_bad} Error!\n    'jq' is missing but required.\n"
        hasDeps=false
    fi

    if ! command -v dig >/dev/null 2>&1; then
        printf "%b" "${check_box_bad} Error!\n    'dig' is missing but required.\n"
        hasDeps=false
    fi

    if ! command -v tput >/dev/null 2>&1; then
        printf "%b" "${check_box_bad} Error!\n    'tput' is missing but required.\n"
        hasDeps=false
     fi

    if [ "${hasDeps}" != true ]; then
        printf "%b" "\n Please install the missing dependencies noted above.\n"
        exit 1
    fi
}

failStartup() {
    moveXOffset; echo "${startup_error}"
    moveXOffset; echo "Exiting."
    exit 1
}

########################################## MAIN FUNCTIONS ##########################################

ShowVersion() {

    GetPADDInformation

    if [ -z "${padd_version_latest}" ]; then
        padd_version_latest="N/A"
    fi

    printf "\n%s${clear_line}\n" "PADD version is ${padd_version_heatmap}${padd_version}${reset_text} (Latest: ${padd_version_latest})"

    exit 0
}

StartupRoutine(){
    local i
    if [ "$1" = "ants" ]; then
        # If the screen is too small from the beginning, exit
        printf "%b" "${check_box_bad} Error!\n    PADD isn't\n    for ants!\n"
        exit 1
    fi

    # Clear the screen and move cursor to (0,0).
    # This mimics the 'clear' command.
    # https://vt100.net/docs/vt510-rm/ED.html
    # https://vt100.net/docs/vt510-rm/CUP.html
    # E3 extension `\033[3J` to clear the scrollback buffer see 'man clear'
    printf '\033[H\033[2J\033[3J'

    # adds the y-offset
    moveYOffset

    if [ "$1" = "pico" ] || [ "$1" = "nano" ] || [ "$1" = "micro" ]; then
        PrintLogo "$1"
        if [ "$1" = "pico" ]; then
            moveXOffset; printf "%b" "START-UP ===========\n"
        elif [ "$1" = "nano" ]; then
            moveXOffset; printf "%b" "START-UP ===============\n"
        else
            moveXOffset; printf "%b" "START-UP =====================\n"
        fi

        # Test if the authentication endpoint is available
        TestAPIAvailability || failStartup

        # Authenticate with the FTL server
        moveXOffset; printf "%b" "Establishing connection with FTL...\n"
        LoginAPI || failStartup

        moveXOffset; printf "%b" "Starting PADD...\n"

        moveXOffset; printf "%b" " [■·········]  10%\r"

        # Request PADD data
        GetPADDData

        # Check for updates
        moveXOffset; printf "%b" " [■■········]  20%\r"
        moveXOffset; printf "%b" " [■■■·······]  30%\r"

        # Get our information for the first time
        moveXOffset; printf "%b" " [■■■■······]  40%\r"
        GetVersionInformation
        moveXOffset; printf "%b" " [■■■■■·····]  50%\r"
        GetSummaryInformation
        moveXOffset; printf "%b" " [■■■■■■····]  60%\r"
        GetPiholeInformation
        moveXOffset; printf "%b" " [■■■■■■■···]  70%\r"
        GetNetworkInformation
        moveXOffset; printf "%b" " [■■■■■■■■··]  80%\r"
        GetSystemInformation
        moveXOffset; printf "%b" " [■■■■■■■■■·]  90%\r"
        GetPADDInformation
        LastCheckPADDInformation=$(date +%s)
        moveXOffset; printf "%b" " [■■■■■■■■■■] 100%\n"

    elif [ "$1" = "mini" ]; then
        PrintLogo "$1"
        moveXOffset; echo "START UP ==============================="

        # Test if the authentication endpoint is available
        TestAPIAvailability || failStartup

        # Authenticate with the FTL server
        moveXOffset; printf "%b" "Establishing connection with FTL...\n"
        LoginAPI || failStartup

        # Request PADD data
        moveXOffset; echo "- Requesting PADD information..."
        GetPADDData

        # Get our information for the first time
        moveXOffset; echo "- Gathering version info."
        GetVersionInformation
        moveXOffset; echo "- Gathering system info."
        GetSystemInformation
        moveXOffset; echo "- Gathering CPU/DNS info."
        GetPiholeInformation
        GetSummaryInformation
        moveXOffset; echo "- Gathering network info."
        GetNetworkInformation
        GetPADDInformation
        LastCheckPADDInformation=$(date +%s)
        if [ "${DOCKER_VERSION}" != "null" ]; then
        moveXOffset; echo "  - Docker Tag ${DOCKER_VERSION}"
        else
        moveXOffset; echo "  - Core ${CORE_VERSION}, Web ${WEB_VERSION}"
        moveXOffset; echo "  - FTL ${FTL_VERSION}, PADD ${padd_version}"
        fi

    else
        PrintLogo "$1"
        if [ "$1" = "tiny" ]; then
        moveXOffset; echo "START UP ============================================"
        else
        moveXOffset; echo "START UP ==================================================="
        fi

        # Test if the authentication endpoint is available
        TestAPIAvailability || failStartup

        # Authenticate with the FTL server
        moveXOffset; printf "%b" "Establishing connection with FTL...\n"
        LoginAPI || failStartup

        # Request PADD data
        moveXOffset; echo "- Requesting PADD information..."
        GetPADDData

        # Get our information for the first time
        moveXOffset; echo "- Gathering version information..."
        GetVersionInformation
        moveXOffset; echo "- Gathering system information..."
        GetSystemInformation
        moveXOffset; echo "- Gathering CPU/DNS information..."
        GetSummaryInformation
        GetPiholeInformation
        moveXOffset; echo "- Gathering network information..."
        GetNetworkInformation

        GetPADDInformation
        LastCheckPADDInformation=$(date +%s)
        if [ "${DOCKER_VERSION}" != "null" ]; then
        moveXOffset; echo "  - Docker Tag ${DOCKER_VERSION}"
        else
        moveXOffset; echo "  - Pi-hole Core ${CORE_VERSION}"
        moveXOffset; echo "  - Web Admin ${WEB_VERSION}"
        moveXOffset; echo "  - FTL ${FTL_VERSION}"
        moveXOffset; echo "  - PADD ${padd_version}"
        fi
    fi

    if [ "${runOnce}" = "false" ]; then
        moveXOffset; printf "%s" "- Starting in "
        for i in 3 2 1
        do
            printf "%s..." "${i}"
            sleep 1
        done
    fi

}

NormalPADD() {
    local now get_network_information_required
    # Trap the window resize signal (handle window resize events)
    trap 'TerminalResize' WINCH


    # Clear the screen once on startup to remove overflow from the startup routine
    printf '\033[2J'

    while true; do

    # Generate layout-dependent output (bars, truncated strings, uptime formatting)
    GenerateSizeDependentOutput "${padd_size}"

    # Sets the message displayed in the "status field" depending on the set flags
    SetStatusMessage

    # Output everything to the screen
    PrintDashboard "${padd_size}"

    # Should we only run once?
    if [ "${runOnce}" = "true" ]; then
        break
    fi

    # Sleep for 5 seconds
    # sending sleep in the background and wait for it
    # this way the TerminalResize trap can kill the sleep
    # and force a instant re-draw of the dashboard
    # https://stackoverflow.com/questions/32041674/linux-how-to-kill-sleep
    #
    # saving the PID of the background sleep process to kill it on exit and resize
    sleep 5 &
    sleepPID=$!
    wait "${sleepPID}"

    # Start getting our information for next round
    now=$(date +%s)

    # Request PADD data after 30 seconds or if the connection was lost
    if [ $((now - LastCheckFullInformation)) -ge 30 ] || [ "${connection_down_flag}" = true ] ; then
        GetPADDData
        LastCheckFullInformation="${now}"
    else
        # Request only a subset of the data
        GetPADDData "?full=false"
    fi

    # If the session has expired, log in again and fetch the data once more
    if [ "${padd_data}" = "401" ]; then
        if Authenticate; then
            GetPADDData
        fi
    fi

    connection_down_flag=false
    # Post-startup recovery: on connection drop (000), failed re-auth (401), or empty jq
    # output, display N/A placeholders and retry on the next 5-second tick
    if [ "${padd_data}" = "000" ] || [ "${padd_data}" = "401" ] || [ -z "${padd_data}" ]; then
        connection_down_flag=true
        GetSystemInformation
        GetSummaryInformation
        GetPiholeInformation
        GetNetworkInformation
        GetVersionInformation
        # set flag to update network information in the next loop in case the connection is re-established
        get_network_information_required=true
    else
        # Get uptime, CPU load, temp, etc. every 5 seconds
        GetSystemInformation
        GetSummaryInformation
        GetPiholeInformation

        if [ $((now - LastCheckNetworkInformation)) -ge 30 ] || [ "${get_network_information_required}" = true ]; then
            GetNetworkInformation
            GetVersionInformation
            LastCheckNetworkInformation="${now}"
            get_network_information_required=false
        fi

        # Get PADD version information every 24hours
        if [ $((now - LastCheckPADDInformation)) -ge 86400 ]; then
            GetPADDInformation
            LastCheckPADDInformation="${now}"
        fi
    fi

  done
}

Update() {
    local padd_script_path tmp_script
    GetPADDInformation

    # GetPADDInformation leaves padd_version_latest empty when GitHub can't be reached
    if [ -z "${padd_version_latest}" ]; then
        echo "${check_box_bad} Cannot check for updates. Is GitHub reachable?"
        exit 1
    fi

    if [ "${padd_out_of_date_flag}" = "true" ]; then
        echo "${check_box_info} Updating PADD from ${padd_version} to ${padd_version_latest}"

        padd_script_path=$(realpath "$0")

        echo "${check_box_info} Downloading PADD update ..."

        tmp_script=$(mktemp) || exit 1
        if ! curl -fsSL --connect-timeout 5 --max-time 20 https://install.padd.sh -o "${tmp_script}" > /dev/null 2>&1 || ! sh -n "${tmp_script}" > /dev/null 2>&1; then
            rm -f "${tmp_script}"
            echo "${check_box_bad} Cannot download PADD update"
            echo "${check_box_info} Go to https://install.padd.sh to download the update manually"
            exit 1
        fi

        if ! cat "${tmp_script}" > "${padd_script_path}"; then
            rm -f "${tmp_script}"
            echo "${check_box_bad} Cannot write to ${padd_script_path}. Check its permissions, or download the update manually"
            exit 1
        fi

        rm -f "${tmp_script}"
        echo "${check_box_good} ... done. Restart PADD for the update to take effect"
    else
        echo "${check_box_good} You are already using the latest PADD version ${padd_version}"
    fi

    exit 0
}

DisplayHelp() {
    cat << EOM

::: PADD displays stats about your Pi-hole!
:::
:::
::: Options:
:::  --xoff [num]    set the x-offset, reference is the upper left corner, disables auto-centering
:::  --yoff [num]    set the y-offset, reference is the upper left corner, disables auto-centering
:::
:::  --server <DOMAIN|IP>    domain or IP of your Pi-hole (default: localhost)
:::  --api <API URL>         API URL location of your Pi-hole (example: https://pi.hole/api/)
:::  --secret <password>     your Pi-hole's password, required to access the API
:::  --2fa <2fa>             your Pi-hole's 2FA code, if 2FA is enabled
:::  --runonce               display output once and exit
:::  -u, --update            update to the latest version
:::  -v, --version           show PADD version info
:::  -h, --help              display this help text

EOM
}

# Called on signals INT QUIT TERM
sig_cleanup() {
    # save error code (130 for SIGINT, 143 for SIGTERM, 131 for SIGQUIT)
    err=$?

    # some shells will call EXIT after the INT signal
    # causing EXIT trap to be executed, so we trap EXIT after INT
    trap '' EXIT

    (exit "${err}") # execute in a subshell just to pass $? to CleanExit()
    CleanExit
}

# Called on signal EXIT, or indirectly on INT QUIT TERM
CleanExit() {
    # save the return code of the script
    err=$?

    # Reset traps for all signals so cleanup is not interrupted by another signal
    trap '' EXIT INT QUIT TERM

    # restore terminal settings if they have been changed (e.g. user canceled script while at password input prompt)
    if [ -n "${stty_orig}" ] && [ "$(stty -g 2>/dev/null)" != "${stty_orig}" ]; then
        stty "${stty_orig}"
    fi

    # Show the cursor
    # https://vt100.net/docs/vt510-rm/DECTCEM.html
    printf '\033[?25h'

    # if background sleep is running, kill it
    # http://mywiki.wooledge.org/SignalTrap#When_is_the_signal_handled.3F
    kill "${sleepPID}" > /dev/null 2>&1

    #  Delete session from FTL server
    DeleteSession
    exit "${err}" # exit the script with saved $?
}

TerminalResize(){
    # if a terminal resize is trapped, check the new terminal size and
    # kill the sleep function within NormalPADD() to trigger redrawing
    # of the Dashboard
    SizeChecker

    # Clear the screen and move cursor to (0,0).
    # This mimics the 'clear' command.
    # https://vt100.net/docs/vt510-rm/ED.html
    # https://vt100.net/docs/vt510-rm/CUP.html
    # E3 extension `\033[3J` to clear the scrollback buffer (see 'man clear')

    printf '\033[H\033[2J\033[3J'

    kill "${sleepPID}" > /dev/null 2>&1
}

main(){

    check_dependencies

    # Hiding the cursor.
    # https://vt100.net/docs/vt510-rm/DECTCEM.html
    printf '\033[?25l'

    # Traps for graceful shutdown
    # https://unix.stackexchange.com/a/681201
    trap CleanExit EXIT
    trap sig_cleanup INT QUIT TERM

    # Save current terminal settings (needed for later restore after password prompt)
    stty_orig=$(stty -g 2>/dev/null)


    SizeChecker

    StartupRoutine "${padd_size}"

    # Run SizeChecker again to account for resizing during startup
    SizeChecker

    # Run PADD
    NormalPADD
}

# Process CLI options; value-taking flags are guarded against missing args ($# -ge 2),
# and --xoff/--yoff reject empty or non-numeric values via case matching.
while [ "$#" -gt 0 ]; do
    case "$1" in
        "-u" | "--update"   ) xOffset=0; doUpdate=true;;
        "-h" | "--help"     ) DisplayHelp; exit 0;;
        "-v" | "--version"  ) xOffset=0; versionOnly=true ;;
        "--runonce"         ) runOnce=true;;
        "--xoff"            ) [ "$#" -ge 2 ] || { DisplayHelp; exit 1; }; case "$2" in ''|*[!0-9]*) DisplayHelp; exit 1 ;; esac; xOffset="${2}"; xOffOrig="${2}"; shift;;
        "--yoff"            ) [ "$#" -ge 2 ] || { DisplayHelp; exit 1; }; case "$2" in ''|*[!0-9]*) DisplayHelp; exit 1 ;; esac; yOffset="${2}"; yOffOrig="${2}"; shift;;
        "--server"          ) [ "$#" -ge 2 ] || { DisplayHelp; exit 1; }; SERVER="${2}"; shift;;
        "--api"             ) [ "$#" -ge 2 ] || { DisplayHelp; exit 1; }; API_LOCATION="${2}"; shift;;
        "--secret"          ) [ "$#" -ge 2 ] || { DisplayHelp; exit 1; }; password="${2}"; shift;;
        "--2fa"             ) [ "$#" -ge 2 ] || { DisplayHelp; exit 1; }; totp="${2}"; shift;;
        *                   ) DisplayHelp; exit 1;;
    esac
    shift
done

if [ -n "${API_LOCATION}" ] && [ -n "${SERVER}" ]; then
    moveXOffset; echo "Do not set --server and --api simultaneously."
    moveXOffset; echo "Exiting."
    exit 1
fi

if [ "${versionOnly}" ]; then
    ShowVersion
fi

if [ "${doUpdate}" ]; then
    Update
fi

main
