#!/usr/bin/env groovy

/**
 * Notify Slack Step
 *
 * Sends notifications to Slack channel.
 *
 * Usage:
 *   notifySlack(channel: '#builds', status: 'SUCCESS', message: 'Build completed')
 */

def call(Map config = [:]) {
    def channel = config.channel ?: env.SLACK_CHANNEL
    def status = config.status ?: 'INFO'
    def message = config.message ?: 'Pipeline notification'
    def credentialsId = config.credentialsId ?: 'slack-webhook'

    if (!channel) {
        echo "No Slack channel configured, skipping notification"
        return
    }

    def color = getColorForStatus(status)
    def emoji = getEmojiForStatus(status)

    def payload = [
        channel: channel,
        username: 'Golden Path Pipeline',
        icon_emoji: ':rocket:',
        attachments: [[
            color: color,
            title: "${emoji} ${env.JOB_NAME} #${env.BUILD_NUMBER}",
            title_link: env.BUILD_URL,
            text: message,
            fields: [
                [title: 'Status', value: status, short: true],
                [title: 'Branch', value: env.GIT_BRANCH ?: 'unknown', short: true],
                [title: 'Commit', value: env.GIT_COMMIT?.take(8) ?: 'unknown', short: true],
                [title: 'Duration', value: currentBuild.durationString?.replace(' and counting', '') ?: 'unknown', short: true]
            ],
            footer: 'Golden Path Pipeline',
            ts: (System.currentTimeMillis() / 1000).toLong()
        ]]
    ]

    try {
        withCredentials([string(credentialsId: credentialsId, variable: 'SLACK_WEBHOOK_URL')]) {
            def payloadJson = groovy.json.JsonOutput.toJson(payload)

            sh """
                curl -s -X POST \
                    -H 'Content-type: application/json' \
                    --data '${payloadJson}' \
                    \${SLACK_WEBHOOK_URL}
            """
        }
        echo "Slack notification sent to ${channel}"
    } catch (Exception e) {
        echo "Warning: Failed to send Slack notification: ${e.message}"
    }
}

def getColorForStatus(String status) {
    switch (status.toUpperCase()) {
        case 'SUCCESS':
            return 'good'  // green
        case 'FAILURE':
        case 'FAILED':
            return 'danger'  // red
        case 'UNSTABLE':
        case 'WARNING':
            return 'warning'  // yellow
        default:
            return '#439FE0'  // blue
    }
}

def getEmojiForStatus(String status) {
    switch (status.toUpperCase()) {
        case 'SUCCESS':
            return ':white_check_mark:'
        case 'FAILURE':
        case 'FAILED':
            return ':x:'
        case 'UNSTABLE':
        case 'WARNING':
            return ':warning:'
        case 'STARTED':
            return ':arrow_forward:'
        default:
            return ':information_source:'
    }
}

/**
 * Send build started notification
 */
def started(Map config = [:]) {
    config.status = 'STARTED'
    config.message = config.message ?: "Build started for ${env.JOB_NAME}"
    call(config)
}

/**
 * Send build success notification
 */
def success(Map config = [:]) {
    config.status = 'SUCCESS'
    config.message = config.message ?: "Build succeeded for ${env.JOB_NAME}"
    call(config)
}

/**
 * Send build failure notification
 */
def failure(Map config = [:]) {
    config.status = 'FAILURE'
    config.message = config.message ?: "Build failed for ${env.JOB_NAME}"
    call(config)
}
