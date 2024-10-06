#!/bin/bash

show_pods() {
    # Displays all the statefulsets on screen for user to interact with

    # Args:
    #   pod_entries (array): Final formatted list of running Pod(s) *This is what the user sees in the menu*
    #   SELECTED_NAMESPACES (array): List of selected namespaces through namespace menu. This function will show all statefulsets in the given previously selected namespaces
    #   pods (array): List of Pods before being spliced for info (like runnning kubectl get pods)
    #       name (string): Pod name
    #       phase (string): Phase of pod (i.e. running, pending, etc)
    #       ready_count (string): How many containers in pod are marked ready
    #       total_count (string): How many total containers are in the pod
    #   pod_selected (string): The user selection entry

    while true; do
        local pod_entries=()    # This resets the list for when you return to this function
        local pod_selected=""   # Must declare variable here... otherwise check for exit code will fail. Exit code will instead capture the success of local declaration

        # Iterate over each selected namespace
        for namespace in "${SELECTED_NAMESPACES[@]}"; do
            local pods=$(kubectl get pods --namespace="$namespace" --no-headers 2>/dev/null)

            if [[ -n $pods ]]; then  # If >=1 pod was found, then continue splice + stitching, otherwise, skip
                # Get pods in the current namespace
                local pods=$(kubectl get pods --namespace="$namespace" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[*].ready,CONTAINERS:.status.containerStatuses[*].name --no-headers)

                while read -r pod; do
                    local name=$(echo $pod | awk '{print $1}')
                    local phase=$(echo $pod | awk '{print $2}')
                    local ready_count=$(kubectl get pod "$name" -o jsonpath='{.status.containerStatuses[*].ready}' --namespace="$namespace" | grep -o true | wc -l)
                    local total_count=$(kubectl get pod "$name" -o jsonpath='{.spec.containers[*].name}' --namespace="$namespace" | wc -w)
                    pod_entries+=("$name" "$phase ($ready_count/$total_count)")
                done <<< "$pods"
            fi
        done

        pod_selected=$(whiptail --title "Pods" --menu "Choose a pod (Press ESC to go HOME):" --cancel-button "Back" 25 125 16 \
        "${pod_entries[@]}" \
        "HOME" "Return to Main Menu" \
        "EXIT" "Exit Script" 3>&1 1>&2 2>&3)

        local exit_code=$?

        # Check if the user wants to return to the main menu or exit
        if [[ $exit_code -ne 0 || $pod_selected == "HOME" ]]; then
            main_menu
        elif [[ $pod_selected == "EXIT" ]]; then
            kill -9 $$  # Hard kill the script
        fi

        # Keypress menu for actions (exec or logs)
        show_options "$pod_selected" "pod" "${SELECTED_NAMESPACES[@]}"
    done
}

exec_into_container() {
    # Gets a shell into the selected container
    # If using bash fails, it uses sh instead

    # Args:
    #   resource_name (string): Selected pod/container
    #   container_name (string): Container's name
    #   SELECTED_NAMESPACES (array): Current selected namespace(s)

    local resource_name="$1"
    local container_name="$2"

    for namespace in "${SELECTED_NAMESPACES[@]}"; do
        kubectl get pods -n $namespace | grep $resource_name > /dev/null 2>&1
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            kubectl exec -it $resource_name -c $container_name --namespace=$namespace -- bash 2>/dev/null || kubectl exec -it $resource_name -c $container_name --namespace=$namespace -- sh 2>/dev/null || \
            echo ">>Failed to connect, bash nor sh are available<<"
            break
        fi
    done


    # echo "kubectl exec -it $resource_name -c $container_name --namespace=$namespace -- bash || kubectl exec -it $resource_name -c $container_name --namespace=$namespace -- sh"
    # kubectl exec -it $resource_name -c $container_name --namespace=$namespace -- bash || kubectl exec -it $resource_name -c $container_name --namespace=$namespace -- sh
}

show_options() {
    # Displays all the options you can do to interact with objects. Pods have more
    # If resource is not a pod, it provides fewer options
    # Performs handle_action at the end

    # Args:
    #   resource_name (string): Pod/svc/statefulset/etc name
    #   resource_type (string): Object type
    #   CONTAINER_ARRAY (array): List of pods as if running kubectl get pods
    #   container_selected (string): Some pods have multiple containers. If so, this stores which you are selecting to interact with
    #       -v0 starts the displayed list at 0. Without that, would require bash math (yuck) to subtract 1 to select the proper item in the array
    #   action (string): User selection

    local resource_name="$1"
    local resource_type="$2"
    local action=""
    local container_selected=""

    if [[ "$resource_type" == "pod" ]]; then
        # Loop over selected namespaces. grep for resource name. If found it, then exit code will be 0
        # If exit code is 0 and it was found, then we can continue
        for namespace in ${SELECTED_NAMESPACES[@]}; do
            kubectl get $resource_type -n $namespace | grep $resource_name > /dev/null 2>&1
            local exit_code=$?

            if [[ $exit_code -eq 0 ]]; then
                # Makes an array of all containers in the pod (usually 1)
                CONTAINER_ARRAY=($(kubectl get pod "$resource_name" --namespace="$namespace" -o jsonpath='{.spec.containers[*].name}'))
            fi
        done

        # If resource is pod, then make list of all containers in Pod. If more than 1 container,
        # then specify which container you wish to proceed with
        # CONTAINER_ARRAY=($(kubectl get pod "$resource_name" --namespace="$NAMESPACE" -o jsonpath='{.spec.containers[*].name}'))

        if [ ${#CONTAINER_ARRAY[@]} -gt 1 ]; then
            # Multiple containers found, prompt to select one
            container_selected=$(whiptail --title "Containers in Pod $resource_name" --menu "Choose a container:" 25 125 16 \
            $(echo "${CONTAINER_ARRAY[@]}" | tr ' ' '\n' | nl -w1 -s' ' -v0) \
            "HOME" "Return to Main Menu" \
            "EXIT" "Exit Script" 3>&1 1>&2 2>&3)

            local exit_code=$?

            # Check if the user wants to return to the main menu or exit
            if [[ $exit_code -ne 0 || $action == "HOME" ]]; then
                main_menu
            elif [[ $action == "EXIT" ]]; then
                kill -9 $$  # Hard kill the script
            fi

        else
            container_selected=${CONTAINER_ARRAY[0]}
        fi

        # Display options (s = SSH, l = logs) in whiptail menu
        action=$(whiptail --title "Action" --menu "Choose an action for $resource_name - ${CONTAINER_ARRAY[$container_selected]} (Press ESC to go HOME):" --cancel-button "Back" 30 125 8 \
        "s" "SSH into container" \
        "l" "View logs" \
        "d" "Describe" \
        "e" "Edit" \
        "D" "Delete" \
        "HOME" "Return to Main Menu" \
        "EXIT" "Exit Script" 3>&1 1>&2 2>&3)

        local exit_code=$?

        # Check if the user wants to return to the main menu or exit
        if [[ $exit_code -ne 0 || $action == "HOME" ]]; then
            main_menu
        elif [[ $action == "EXIT" ]]; then
            kill -9 $$  # Hard kill the script
        fi
    else
        action=$(whiptail --title "Action" --menu "Choose an action for $resource_name (Press ESC to go HOME):" --cancel-button "Back" 30 125 8 \
        "d" "Describe" \
        "e" "Edit" \
        "D" "Delete" \
        "HOME" "Return to Main Menu" \
        "EXIT" "Exit Script" 3>&1 1>&2 2>&3)

        local exit_code=$?

        # Check if the user wants to return to the main menu or exit
        if [[ $exit_code -ne 0 || $action == "HOME" ]]; then
            main_menu
        elif [[ $action == "EXIT" ]]; then
            kill -9 $$  # Hard kill the script
        fi
    fi

    handle_action "$resource_name" "$resource_type" "$container_selected" "$action" "${SELECTED_NAMESPACES[@]}" "$CONTAINER_ARRAY"
}


edit_yaml() {
    # Edit the yaml of the selected resource

    # Args:
    #   resource_type (string): Pod,svc,statefulset, etc...
    #   resource_name (string): Pod,svc,statefulset, etc. name
    #   selected_namespaces (array): Current selected namespace(s)

    local resource_type="$1"
    local resource_name="$2"

    # Loop over selected namespaces. grep for resource name. If found it, then exit code will be 0
    # If exit code is 0 and it was found, then we can continue to edit
    for namespace in "${SELECTED_NAMESPACES[@]}"; do
        kubectl get $resource_type -n $namespace | grep $resource_name > /dev/null 2>&1
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            kubectl edit $resource_type $resource_name -n $namespace
        fi
    done
}

delete_resource() {
    # Delete selected resource

    # Args:
    #   resource_type (string): pod,svc,statefulset, etc...
    #   resource_name (string): pod,svc,statefulset, etc. name
    #   selected_namespaces (string): Current selected namespace

    local resource_type="$1"
    local resource_name="$2"
    local selected_namespaces="$3"

    for namespace in ${selected_namespaces[@]}; do
        kubectl delete $resource_type $resource_name -n $namespace &
    done
}

handle_action() {
    # These are the options, but what is displayed is handled by show_options()
    # This case below has everything available...even things like ssh and logs
    # Obviously svcs can't do that, but it's okay bc the options won't appear :)

    # Args:
    #   resource_type (string): Pod,svc,statefulset, etc...
    #   resource_name (string): Pod,svc,statefulset, etc. name
    #   NAMESPACE (string): Current selected namespace
    #   CONTAINER_ARRAY (array): List of pods (used to get the container name)
    #       container_selected (string): SelRESOURCE_TYPE
    #   action (string): Selected action from show_options()
    #   SELECTED_NAMESPACES (array): List of previously selected namespaces

    local resource_name="$1"
    local resource_type="$2"
    local container_selected="$3"
    local action="$4"
    CONTAINER_ARRAY="$CONTAINER_ARRAY"

    case $action in
        s)
            exec_into_container "$resource_name" "${CONTAINER_ARRAY[$container_selected]}" "${SELECTED_NAMESPACES[@]}"
            ;;
        l)
            show_logs "$resource_name" "${CONTAINER_ARRAY[$container_selected]}" "${SELECTED_NAMESPACES[@]}"
            ;;
        d)
            describe_resource "$resource_type" "$resource_name" "${SELECTED_NAMESPACES[@]}"
            ;;
        e)
            edit_yaml "$resource_type" "$resource_name" "${SELECTED_NAMESPACES[@]}"
            ;;
        D)
            delete_resource "$resource_type" "$resource_name" "${SELECTED_NAMESPACES[@]}"
            ;;
        *)
            echo "Invalid choice." ;;
    esac
}

describe_resource() {
    # Describe the resource

    # Args:
    #   resource_type (string): Pod,svc,statefulset, etc...
    #   resource_name (string): Pod,svc,statefulset, etc. name
    #   NAMESPACE (string): Current selected namespace
    #   output (string): Checks if less output is empty (if the loop lands on wrong namespace for the resource)
    #       > Unfortunately this is the best / cleanest quick thing I could come up with right now
    #   exit_code (string technically): 0 or non-zero. 0 is produced is previous command was success

    local resource_type="$1"
    local resource_name="$2"

    # Loop over selected namespaces. grep for resource name. If found it, then exit code will be 0
    # If exit code is 0 and it was found, then we can continue to describe
    for namespace in ${SELECTED_NAMESPACES[@]}; do
        kubectl get $resource_type -n $namespace | grep $resource_name > /dev/null 2>&1
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            kubectl describe $resource_type $resource_name -n $namespace | less
            break
        fi
    done
}


show_logs() {
    # Get logs of pod/container

    # Args:
    #   resource_name (string): pod name
    #   container_name (string): container name
    #   SELECTED_NAMESPACES (array): Current selected namespace

    local resource_name="$1"
    container_name="$2"
    
    whiptail --title "Getting Logs" --msgbox "Press 'CTRL+c' to stop following and to scroll through history. Then 'q' to quit." 10 100 4

    for namespace in "${SELECTED_NAMESPACES[@]}"; do
        kubectl get pods -n $namespace | grep $resource_name > /dev/null 2>&1
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            kubectl logs $resource_name -c $container_name -n $namespace -f | less
            break
        fi
    done
}

show_services() {
    # Shows all svcs for given namespaces
    # Performs handle_action at the end

    # Args:
    #   svc_entries (array): List of svcs in given namespaces **This is what the user sees in the menu*
    #   SELECTED_NAMESPACES (array): List of selected namespaces through namespace menu. This function will show all svcs in the given previously selected namespaces
    #       name (string): Svc name
    #       type (string): Object type, i.e., clusterIP, LB, nodePort, etc
    #       cluster_ip (string): IP addr.
    #       external_ip (string): IP addr.
    #       port (string): Svc port
    #   svc_selected (string): User selected entry

    local svc_selected=""       # Must declare variable here... otherwise check for exit code will fail. Exit code will instead capture the success of local declaration

    while true; do
        local svc_entries=()    # This resets the list for when you return to this function

        # Iterate over each selected namespace, splice, and stitch info
        for namespace in "${SELECTED_NAMESPACES[@]}"; do
            local svcs=$(kubectl get svc --namespace="$namespace" --no-headers 2>/dev/null)

            if [[ -n $svcs ]]; then     # If >=1 svc was found, then continue splice + stitching, otherwise, skip
                while read -r svc; do
                    local name=$(echo $svc | awk '{print $1}')
                    local type=$(echo $svc | awk '{print $2}')
                    local cluster_ip=$(echo $svc | awk '{print $3}')
                    local external_ip=$(echo $svc | awk '{print $4}')
                    local port=$(echo $svc | awk '{print $5}')
                    svc_entries+=("$name" "$type $cluster_ip, EXT-IP: $external_ip, $port, NS: $namespace")
                done <<< "$svcs"
            fi
        done
        
        svc_selected=$(whiptail --title "Services" --menu "(Press ESC to go HOME):" --cancel-button "Back" 25 200 16 \
        "${svc_entries[@]}" \
        "HOME" "Return to Main Menu" \
        "EXIT" "Exit Script" 3>&1 1>&2 2>&3)
        
        # Check if the user wants to return to the main menu or exit
        if [[ $? -ne 0 || $svc_selected == "HOME" ]]; then
            main_menu
        elif [[ $svc_selected == "EXIT" ]]; then
            kill -9 $$  # Hard kill the script
        fi

        # show_options $SVC_SELECTED "svc" $namespace
        show_options "$svc_selected" "svc" "${SELECTED_NAMESPACES[@]}"
    done
}

show_deployments() {
    # Shows all deployments for given namespaces
    # Performs handle_action at the end

    # Args:
    #   depl_entries (array): List of deployments in given namespaces **This is what the user sees in the menu*
    #   SELECTED_NAMESPACES (array): List of selected namespaces through namespace menu. This function will show all svcs in the given previously selected namespaces
    #       name (string): Name of deployment
    
    while true; do
        local depl_entries=()   # This resets the list for when you return to this function
        local depl_selected=""  # Must declare variable here... otherwise check for exit code will fail. Exit code will instead capture the success of local declaration

        for namespace in "${SELECTED_NAMESPACES[@]}"; do
            local depls=$(kubectl get deployment --namespace="$namespace" --no-headers 2>/dev/null)

            if [[ -n $depls ]]; then # If >=1 deployment was found, then continue splice + stitching, otherwise, skip
                local depls=$(kubectl get deployments --namespace=$namespace -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,REPLICAS:.spec.replicas --no-headers)

                while read -r depl; do
                    local name=$(echo $depl | awk '{print $1}')
                    local ready=$(echo $depl | awk '{print $2}')
                    local replicas=$(echo $depl | awk '{print $3}')
                    depl_entries+=("$name" "Ready: $ready, Replicas: $replicas")
                done <<< "$depls"
            fi
        done

        depl_selected=$(whiptail --title "Deployments" --menu "Deployment list (Press ESC to go HOME):" 25 125 16 "${depl_entries[@]}" \
        "HOME" "Return to Main Menu" \
        "EXIT" "Exit Script" 3>&1 1>&2 2>&3)
        
        local exit_code=$?

        # Check if the user wants to return to the main menu or exit
        if [[ $exit_code -ne 0 || $depl_selected == "HOME" ]]; then
            main_menu
        elif [[ $depl_selected == "EXIT" ]]; then
            kill -9 $$  # Hard kill the script
        fi

        show_options $depl_selected "deployment" $namespace
        
    done
}

show_statefulsets() {
    # Displays all the statefulsets on screen for user to interact with
    # Performs handle_action at the end


    # Args:
    #   stflst_entries (array): Final list of running statefulset(s) name, status, and num. of replicas. *This is what the user sees in the menu*
    #   SELECTED_NAMESPACES (array): List of selected namespaces through namespace menu. This function will show all statefulsets in the given previously selected namespaces
    #   stflsts (array): List of statefulsets before being spliced for info (like runnning kubectl get statefulset)
    #       stflst (string): A line of the kubectl output
    #       name (string): Statefulset name
    #       READY (string): Representation if statefulset is ready
    #       REPLICAS (string): Number of replicas
    #   STFLST_SELECTED (string): The user selection entry

    while true; do
        local stflst_entries=()
        local stflst_selected=""

        for namespace in "${SELECTED_NAMESPACES[@]}"; do
            local stflsts=$(kubectl get statefulset --namespace="$namespace" --no-headers 2>/dev/null)

            if [[ -n $stflsts ]]; then  # If >=1 statefulset was found, then continue splice + stitching, otherwise, skip
                stflsts=$(kubectl get statefulset --namespace=$namespace -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,REPLICAS:.spec.replicas --no-headers)

                while read -r stflst; do
                    local name=$(echo $stflst | awk '{print $1}')
                    local ready=$(echo $stflst | awk '{print $2}')
                    local replicas=$(echo $stflst | awk '{print $3}')
                    stflst_entries+=("$name" "Ready: $ready, Replicas: $replicas")
                done <<< "$stflsts"
            fi
        done

        stflst_selected=$(whiptail --title "Statefulset" --menu "Statefulset list (Press ESC to go HOME):" 25 125 16 "${stflst_entries[@]}" \
        "HOME" "Return to Main Menu" \
        "EXIT" "Exit Script" 3>&1 1>&2 2>&3)

        local exit_code=$?

        # Check if the user wants to return to the main menu or exit
        if [[ $exit_code -ne 0 || $stflst_selected == "HOME" ]]; then
            main_menu
        elif [[ $stflst_selected == "EXIT" ]]; then
            kill -9 $$  # Hard kill the script
        fi

        show_options $stflst_selected "statefulset" $namespace

    done
}

show_namespaces() {
    # Shows all namespaces and allows user to select all that wish to be viewed
    # Defaults to "default" namespace
    # Performs handle_action at the end

    # Args:
    #   SELECTED_NAMESPACES (array): List of selected namespaces chosen
    #   CHECKLIST_OPTIONS (array): List of what was checked by user

    # Initialize empty arrays for namespaces and statuses
    SELECTED_NAMESPACES=()
    NAMESPACES=()
    CHECKLIST_OPTIONS=()
    
    # Read the output of the kubectl command, split to namespace names, append to array
    while IFS= read -r line; do
        namespace=$(echo $line | awk '{print $1}')
        NAMESPACES+=("$namespace")
    done < <(kubectl get namespaces -o custom-columns=NAME:.metadata.name --no-headers)
    
    # Build the checklist options
    for namespace in "${NAMESPACES[@]}"; do
        CHECKLIST_OPTIONS+=("$namespace" "" "OFF")
    done
    
    # Use checklist to select namespaces
    SELECTED_NAMESPACES=$(whiptail --title "Select Namespaces" --checklist "Choose namespaces (Press SPACE to select):" 25 75 16 "${CHECKLIST_OPTIONS[@]}" 3>&1 1>&2 2>&3)
    
    # Remove quotes and convert the selected namespaces string to an array
    SELECTED_NAMESPACES=$(echo $SELECTED_NAMESPACES | sed 's/"//g')
    IFS=' ' read -r -a SELECTED_NAMESPACES <<< "$SELECTED_NAMESPACES"

    if [[ ${#SELECTED_NAMESPACES[@]} -eq 0 ]]; then         # Checks number of boxes selected, if 0, then chooses default NS
        echo "No namespaces selected, choosing default"
        SELECTED_NAMESPACES=(default)
    fi
}

help_page() {
    HELP_TEXT="Welcome to B9s v1.0!

                                                                   888888   eeeee      
                                                                   8    8   8   8  eeeee
                                                                   8eeee8ee 8eee8  8   
                                                                   88     8    88  8eeee
                                                                   88     8    88      8
                                                                   88eeeee8    88  8ee88

    B9s is a K9s-like tool for limited-access Linux systems

    Usage:
    - HOME should always take you back to the first screen. You can also press the ESC key to go home. EXIT will..well..exit
    - Use arrow keys and enter/return key to navigate
    - Tab will move your cursor to the OK/Cancel/HOME/EXIT options below
    
    NOTE:
    - List of objects does not refresh automatically
    - If logs are long and you quit before all are loaded, it might take a little bit for it to try to finish showing logs...
        - If needed you can ctrl+c and restart the app
    - Not all options are available like in K9s
    - There are effectively no keyboard shortcuts options available for this. Some letters are indicated will work, but numbers do not
    - When viewing logs of a pod, it will **follow**. To break the follow, press ctrl+c and then it's the normal 'less' command (q to quit)
    - Default namespace selected is 'default'. You may select one or more in the namespaces tab to view multiple
    
    >>> Reminder: This was a quick weekend project because I wanted it. It only has some of the common uses of k9s"

    # Display the help text using Whiptail
    whiptail --title "Help Page" --scrolltext --ok-button "HOME" --cancel-button "EXIT" --msgbox "$HELP_TEXT" 35 155

}

# Main menu function
main_menu() {
    ASCII="
888888   eeeee      
8    8   8   8  eeeee
8eeee8ee 8eee8  8   
88     8    88  8eeee
88     8    88      8
88eeeee8    88  8ee88
"

    while true; do
        CHOICE=$(whiptail --title "Please Select an Option" --menu "$ASCII" 30 125 15 \
        "1" "Show Pods" \
        "2" "Show Services" \
        "3" "Show Deployments" \
        "4" "Show Statefulsets" \
        "5" "Select Namespaces" \
        "6" "Help" \
        "7" "Exit" 3>&1 1>&2 2>&3)

        case $CHOICE in
            1) show_pods ;;
            2) show_services ;;
            3) show_deployments ;;
            4) show_statefulsets ;;
            5) show_namespaces ;;
            6) help_page ;;
            7) exit 0 ;;
            *) echo "Invalid option." ;;
        esac
    done
}

# Start with default namespace selected
SELECTED_NAMESPACES=(default)
export NEWT_COLORS='
root=,black
border=cyan,black
title=blue,black
roottext=blue,black
window=black,black
textbox=white,black
button=black,cyan
compactbutton=white,black
listbox=white,black
actlistbox=black,white
actsellistbox=black,cyan
checkbox=cyan,black
actcheckbox=black,cyan
'

main_menu
