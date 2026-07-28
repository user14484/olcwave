import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
    settingsApi,
    type RuntimeSettings,
    type RemnawaveSettingsUpdate,
} from '../api/settings'
import { useAuthStore } from '../store/auth'
import { useLanguage, type TranslationKey } from '../i18n/useLanguage'
import Button from '../components/ui/Button'
import Input from '../components/ui/Input'
import Select from '../components/ui/Select'
import { Card, CardHeader } from '../components/ui/Misc'
import { ToastContainer } from '../components/containers/Toast'
import { useToasts } from '../components/containers/useToasts'
import { bytesToGB, gbToBytes } from '../utils/format'
import {
    ArrowLeftOnRectangleIcon,
    ExclamationTriangleIcon,
} from '@heroicons/react/24/outline'

const RW_SYNC_OPTIONS: { value: string; labelKey: TranslationKey }[] = [
    { value: '1m', labelKey: 'everyMinute' },
    { value: '5m', labelKey: 'every5Minutes' },
    { value: '15m', labelKey: 'every15Minutes' },
    { value: '1h', labelKey: 'everyHour' },
    { value: '6h', labelKey: 'every6Hours' },
    { value: '12h', labelKey: 'every12Hours' },
    { value: '24h', labelKey: 'onceADay' },
    { value: '__other__', labelKey: 'other' },
]

function isValidInterval(val: string): boolean {
    return /^[1-9]\d*[smh]$/.test(val)
}

function isValidDuration(val: string): boolean {
    return /^[1-9]\d*[mhd]$/.test(val)
}

function parseDurationMinutes(val: string): number | null {
    const match = val.match(/^(\d+)([mhd])$/)
    if (!match) return null
    const number = parseInt(match[1], 10)
    const unit = match[2]
    const multiplier: Record<string, number> = { m: 1, h: 60, d: 1440 }
    return number * multiplier[unit]
}

function getDurationError(val: string, tr: (key: TranslationKey) => string): string {
    if (!isValidDuration(val)) {
        return tr('invalidFormatDuration')
    }
    const minutes = parseDurationMinutes(val)
    if (minutes === null) return tr('invalidDuration')
    if (minutes < 5) return tr('intervalMin5m')
    if (minutes > 43200) return tr('intervalMax30d')
    return ''
}

function formatDatetime(iso: string | null): string {
    if (!iso) return '—'
    const d = new Date(iso)
    return d.toLocaleDateString() + ' ' + d.toLocaleTimeString()
}

export default function Settings() {
    const { t } = useLanguage()
    const logout = useAuthStore((s) => s.logout)
    const { toasts, dismiss, success, error: toastError } = useToasts()
    const queryClient = useQueryClient()

    const { data: settings, isLoading } = useQuery({
        queryKey: ['settings'],
        queryFn: () => settingsApi.get().then((r) => r.data),
    })
    const { data: remnawaveSettings, isLoading: isRemnawaveLoading } = useQuery({
        queryKey: ['settings', 'remnawave'],
        queryFn: () => settingsApi.getRemnawave().then((r) => r.data),
    })

    const [subName, setSubName] = useState('')
    const [defaultTrafficGb, setDefaultTrafficGb] = useState('')
    const [subUpdateInterval, setSubUpdateInterval] = useState('')
    const [collectInterval, setCollectInterval] = useState('')
    const [syncMode, setSyncMode] = useState('1h')
    const [customSync, setCustomSync] = useState('')
    const [lastSyncAt, setLastSyncAt] = useState<string | null>(null)
    const [rwApiUrl, setRwApiUrl] = useState('')
    const [rwApiToken, setRwApiToken] = useState('')
    const [rwCaddyToken, setRwCaddyToken] = useState('')
    const [rwApiTokenConfigured, setRwApiTokenConfigured] = useState(false)
    const [rwCaddyTokenConfigured, setRwCaddyTokenConfigured] = useState(false)


    useEffect(() => {
        if (!settings) return

        setSubName(settings.sub_name)
        setDefaultTrafficGb(bytesToGB(settings.default_traffic_limit).toFixed(2))
        setSubUpdateInterval(settings.sub_update_interval)
        setCollectInterval(String(settings.traffic_collect_interval))
        if (RW_SYNC_OPTIONS.some(o => o.value === settings.sync_interval)) {
            setSyncMode(settings.sync_interval)
            setCustomSync('')
        } else {
            setSyncMode('__other__')
            setCustomSync(settings.sync_interval)
        }
        setLastSyncAt(settings.last_sync_at)
    }, [settings])

    const saveMutation = useMutation({
        mutationFn: (data: RuntimeSettings) => settingsApi.update(data).then((r) => r.data),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['settings'] })
            success(t('settingsSaved'))
        },
        onError: (err) => {
            toastError(
                (err as { response?: { data?: { detail?: string } } })?.response?.data?.detail ||
                t('failedToSaveSettings'),
            )
        },
    })

    const saveRemnawaveMutation = useMutation({
        mutationFn: (data: RemnawaveSettingsUpdate) =>
            settingsApi.updateRemnawave(data).then((r) => r.data),

        onSuccess: (data) => {
            setRwApiToken('')
            setRwCaddyToken('')
            setRwApiTokenConfigured(data.rw_api_token_configured)
            setRwCaddyTokenConfigured(data.rw_caddy_token_configured)

            queryClient.invalidateQueries({
                queryKey: ['settings', 'remnawave'],
            })

            success('Настройки Remnawave сохранены')
        },
        onError: (err) => {
            toastError(
                (err as { response?: { data?: { detail?: string } } })
                    ?.response?.data?.detail ||
                'Не удалось сохранить настройки Remnawave',
            )
        },
    })

    const testRemnawaveMutation = useMutation({
        mutationFn: (data: RemnawaveSettingsUpdate) =>
            settingsApi.testRemnawave(data).then((r) => r.data),

        onSuccess: (data) => {
            if (data.remnawave.success) {
                success(data.remnawave.message)
            } else {
                toastError(data.remnawave.message)
            }

            if (!data.caddy.success) {
                toastError(data.caddy.message)
            }
        },

        onError: (err) => {
            toastError(
                (err as { response?: { data?: { detail?: string } } })
                    ?.response?.data?.detail ||
                'Не удалось проверить подключение',
            )
        },
    })

    useEffect(() => {
        if (!remnawaveSettings) return

        setRwApiUrl(remnawaveSettings.rw_api_url)
        setRwApiTokenConfigured(remnawaveSettings.rw_api_token_configured)
        setRwCaddyTokenConfigured(remnawaveSettings.rw_caddy_token_configured)
    }, [remnawaveSettings])

    const isCustom = syncMode === '__other__'
    const effectiveSync = isCustom
        ? customSync
        : syncMode
    const syncError = isCustom && customSync && !isValidInterval(customSync) ? t('invalidFormatNumberSuffix') : ''
    const subIntervalError = subUpdateInterval ? getDurationError(subUpdateInterval, t) : ''

    const handleSave = () => {
        saveMutation.mutate({
            sub_name: subName,
            default_traffic_limit: gbToBytes(parseFloat(defaultTrafficGb) || 0),
            sub_update_interval: subUpdateInterval || '1h',
            traffic_collect_interval: parseInt(collectInterval, 10) || 10,
            sync_interval: effectiveSync || '1h',
            last_sync_at: lastSyncAt,
        })
    }

    const handleSaveRemnawave = () => {
        saveRemnawaveMutation.mutate({
            rw_api_url: rwApiUrl,
            rw_api_token: rwApiToken,
            rw_caddy_token: rwCaddyToken,
        })
    }

    const handleTestRemnawave = () => {
        testRemnawaveMutation.mutate({
            rw_api_url: rwApiUrl,
            rw_api_token: rwApiToken,
            rw_caddy_token: rwCaddyToken,
        })
    }

    const handleSyncSelect = (value: string) => {
        setSyncMode(value)

        if (value !== '__other__') {
            setCustomSync('')
        }
    }

    return (
        <div className="max-w-2xl space-y-5">
            <Card>
                <CardHeader title={t('trafficSettingsTitle')} />
                <div className="px-5 py-4 space-y-4">
                    <Input
                        label={t('subscriptionName')}
                        value={subName}
                        onChange={(e) => setSubName(e.target.value)}
                        placeholder={t('myVpn')}
                        hint={t('serviceNameHint')}
                        disabled={isLoading}
                    />
                    <Input
                        label={t('defaultTrafficLimitGb')}
                        type="number"
                        min="0"
                        step="0.1"
                        value={defaultTrafficGb}
                        onChange={(e) => setDefaultTrafficGb(e.target.value)}
                        placeholder={t('trafficLimitPlaceholder')}
                        hint={t('defaultTrafficHint')}
                        disabled={isLoading}
                    />
                    <Input
                        label={t('subscriptionUpdateInterval')}
                        value={subUpdateInterval}
                        onChange={(e) => setSubUpdateInterval(e.target.value)}
                        placeholder="e.g. 1h"
                        hint={t('subIntervalHint')}
                        error={subIntervalError}
                        disabled={isLoading}
                    />
                    <Input
                        label={t('trafficCollectInterval')}
                        type="number"
                        min="1"
                        step="1"
                        value={collectInterval}
                        onChange={(e) => setCollectInterval(e.target.value)}
                        placeholder="e.g. 10"
                        hint={t('trafficCollectHint')}
                        disabled={isLoading}
                    />
                    <div className="flex justify-end pt-1">
                        <Button
                            onClick={handleSave}
                            loading={saveMutation.isPending}
                            disabled={isLoading || !!subIntervalError}
                        >
                            Сохранить
                        </Button>
                    </div>
                </div>
            </Card>

            <Card>
                <CardHeader title={t('remnawaveSync')} />
                <div className="px-5 py-4 space-y-4">

                    <Input
                        label="Адрес Remnawave"
                        value={rwApiUrl}
                        onChange={(e) => setRwApiUrl(e.target.value)}
                        placeholder="https://remnawave.example.com"
                        disabled={isRemnawaveLoading}
                    />

                    <Input
                        label="API Token"
                        type="password"
                        value={rwApiToken}
                        onChange={(e) => setRwApiToken(e.target.value)}
                        placeholder={rwApiTokenConfigured ? 'Токен уже настроен' : 'Введите API Token'}
                        hint={
                            rwApiTokenConfigured
                                ? 'Оставьте пустым, чтобы не менять текущий токен'
                                : undefined
                        }
                        disabled={isRemnawaveLoading}
                    />

                    <Input
                        label="Caddy Auth Token"
                        type="password"
                        value={rwCaddyToken}
                        onChange={(e) => setRwCaddyToken(e.target.value)}
                        placeholder={
                            rwCaddyTokenConfigured
                                ? 'Caddy Token уже настроен'
                                : 'Оставьте пустым, если Caddy Auth не используется'
                        }
                        hint={
                            rwCaddyTokenConfigured
                                ? 'Оставьте пустым, чтобы не менять текущий токен'
                                : undefined
                        }
                        disabled={isRemnawaveLoading}
                    />
                    <Select
                        label={t('autoSyncUsers')}
                        options={RW_SYNC_OPTIONS.map((o) => ({ value: o.value, label: t(o.labelKey) }))}
                        value={syncMode}
                        onChange={(e) => handleSyncSelect(e.target.value)}
                        disabled={isLoading}
                    />
                    {isCustom && (
                        <Input
                            label={t('customInterval')}
                            value={customSync}
                            onChange={(e) => setCustomSync(e.target.value)}
                            placeholder="e.g. 10m"
                            error={syncError}
                            hint={t('customIntervalHint')}
                            disabled={isLoading}
                        />
                    )}
                    <div className="flex items-center justify-between gap-4 py-2 border-t border-border">
                        <span className="text-xs text-text-muted">{t('lastSync')}</span>
                        <span className="text-xs text-text-primary tabular-nums">{formatDatetime(lastSyncAt)}</span>
                    </div>
                    <div className="flex justify-end gap-2 pt-1">
                        <Button
                            variant="secondary"
                            onClick={handleTestRemnawave}
                            loading={testRemnawaveMutation.isPending}
                            disabled={
                                isRemnawaveLoading ||
                                saveRemnawaveMutation.isPending ||
                                !rwApiUrl
                            }
                        >
                            Проверить подключение
                        </Button>

                        <Button
                            onClick={handleSaveRemnawave}
                            loading={saveRemnawaveMutation.isPending}
                            disabled={
                                isRemnawaveLoading ||
                                testRemnawaveMutation.isPending ||
                                !rwApiUrl
                            }
                        >
                            Сохранить подключение
                        </Button>
                    </div>
                </div>
            </Card>

            <Card className="border-danger/20">
                <div className="px-5 py-3.5 border-b border-danger/20 flex items-center gap-2">
                    <ExclamationTriangleIcon className="w-4 h-4 text-danger" />
                    <h3 className="text-xs font-semibold text-danger uppercase tracking-wider">{t('dangerZone')}</h3>
                </div>
                <div className="p-5 flex items-center justify-between gap-4">
                    <div>
                        <p className="text-sm font-medium text-text-primary">{t('signOut')}</p>
                        <p className="text-xs text-text-muted mt-0.5">{t('signOutDescription')}</p>
                    </div>
                    <Button variant="danger" onClick={logout}>
                        <ArrowLeftOnRectangleIcon className="w-4 h-4" />
                        {t('logout')}
                    </Button>
                </div>
            </Card>

            <ToastContainer toasts={toasts} onDismiss={dismiss} />
        </div>
    )
}
