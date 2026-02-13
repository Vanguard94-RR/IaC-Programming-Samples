#!/bin/bash
# GNP Ticket Navigation Functions
# Source this file in your .bashrc or .zshrc for persistent functions

# Function to navigate to any ticket directory
goto_ticket() {
    local ticket="$1"
    if [[ -z "$ticket" ]]; then
        echo "Usage: goto_ticket TICKET_ID"
        echo "Example: goto_ticket CTASK1234567"
        return 1
    fi
    
    local ticket_upper="$(echo "$ticket" | tr '[:lower:]' '[:upper:]')"
    local ticket_dir="/home/admin/Documents/GNP/Tickets/$ticket_upper"
    
    if [[ -d "$ticket_dir" ]]; then
        cd "$ticket_dir"
        echo "📂 Navigated to ticket: $ticket_upper"
        echo "📍 Current directory: $(pwd)"
        if [[ -f "README.md" ]]; then
            echo ""
            echo "📋 README preview:"
            head -10 README.md
        fi
    else
        echo "❌ Ticket directory not found: $ticket_dir"
        return 1
    fi
}

# Function to list all ticket directories
list_tickets() {
    local tickets_root="/home/admin/Documents/GNP/Tickets"
    if [[ -d "$tickets_root" ]]; then
        echo "📂 Available tickets:"
        for dir in "$tickets_root"/*/; do
            if [[ -d "$dir" ]]; then
                local ticket_name="$(basename "$dir")"
                local created_date=""
                if [[ -f "$dir/README.md" ]]; then
                    created_date=$(grep "Date:" "$dir/README.md" | cut -d: -f2- | xargs)
                fi
                echo "  🎫 $ticket_name ${created_date:+($created_date)}"
            fi
        done
    else
        echo "❌ Tickets directory not found: $tickets_root"
    fi
}
