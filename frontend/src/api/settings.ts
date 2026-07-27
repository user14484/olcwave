import api from './client'

export interface RuntimeSettings {
    sub_name: string
    default_traffic_limit: number
    sub_update_interval: string
    traffic_collect_interval: number
    sync_interval: string
    last_sync_at: string | null
}

export interface RemnawaveSettings {
    rw_api_url: string
    rw_api_token_configured: boolean
    rw_caddy_token_configured: boolean
}

export interface RemnawaveSettingsUpdate {
    rw_api_url: string
    rw_api_token: string
    rw_caddy_token: string
}

export interface RemnawaveConnectionResult {
    success: boolean
    message: string
}

export interface RemnawaveTestResponse {
    remnawave: RemnawaveConnectionResult
    caddy: RemnawaveConnectionResult
}

export const settingsApi = {
    get: () =>
        api.get<RuntimeSettings>('/settings/'),

    update: (data: RuntimeSettings) =>
        api.put<RuntimeSettings>('/settings/', data),

    getRemnawave: () =>
        api.get<RemnawaveSettings>('/settings/remnawave'),

    updateRemnawave: (data: RemnawaveSettingsUpdate) =>
        api.put<RemnawaveSettings>('/settings/remnawave', data),

    testRemnawave: (data: RemnawaveSettingsUpdate) =>
        api.post<RemnawaveTestResponse>('/settings/remnawave/test', data),
}