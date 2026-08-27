package com.cytatv.wifihub;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.wifi.ScanResult;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.os.Bundle;
import android.provider.Settings;
import android.text.InputType;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class MainActivity extends Activity {
    private WifiManager wifi;
    private TextView status;
    private ListView list;
    private final List<ScanResult> networks = new ArrayList<ScanResult>();
    private ArrayAdapter<String> adapter;

    private final BroadcastReceiver scanReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            refreshList();
        }
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.main);
        wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        status = (TextView) findViewById(R.id.status);
        list = (ListView) findViewById(R.id.list);
        adapter = new ArrayAdapter<String>(this, android.R.layout.simple_list_item_1, new ArrayList<String>()) {
            @Override public View getView(int position, View convertView, ViewGroup parent) {
                View v = super.getView(position, convertView, parent);
                TextView tv = (TextView) v.findViewById(android.R.id.text1);
                tv.setTextColor(0xFFFFFFFF);
                tv.setTextSize(20f);
                tv.setPadding(24, 28, 24, 28);
                return v;
            }
        };
        list.setAdapter(adapter);

        ((Button) findViewById(R.id.btn_toggle)).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                boolean on = wifi.isWifiEnabled();
                wifi.setWifiEnabled(!on);
                updateStatus();
                Toast.makeText(MainActivity.this, on ? "Wi‑Fi выключается…" : "Wi‑Fi включается…", Toast.LENGTH_SHORT).show();
            }
        });
        ((Button) findViewById(R.id.btn_scan)).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (!wifi.isWifiEnabled()) {
                    wifi.setWifiEnabled(true);
                    Toast.makeText(MainActivity.this, "Включаю Wi‑Fi…", Toast.LENGTH_SHORT).show();
                }
                boolean ok = wifi.startScan();
                Toast.makeText(MainActivity.this, ok ? "Сканирование…" : "Скан не удался", Toast.LENGTH_SHORT).show();
                refreshList();
            }
        });
        ((Button) findViewById(R.id.btn_system)).setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                try {
                    startActivity(new Intent(Settings.ACTION_WIFI_SETTINGS));
                } catch (Exception e) {
                    try {
                        startActivity(new Intent(Settings.ACTION_WIRELESS_SETTINGS));
                    } catch (Exception e2) {
                        Toast.makeText(MainActivity.this, "Системный экран недоступен", Toast.LENGTH_LONG).show();
                    }
                }
            }
        });
        list.setOnItemClickListener(new android.widget.AdapterView.OnItemClickListener() {
            @Override public void onItemClick(android.widget.AdapterView<?> parent, View view, int position, long id) {
                if (position < 0 || position >= networks.size()) return;
                connectDialog(networks.get(position));
            }
        });
    }

    @Override protected void onResume() {
        super.onResume();
        registerReceiver(scanReceiver, new IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION));
        updateStatus();
        refreshList();
        if (wifi.isWifiEnabled()) wifi.startScan();
    }

    @Override protected void onPause() {
        super.onPause();
        try { unregisterReceiver(scanReceiver); } catch (Exception ignored) {}
    }

    private void updateStatus() {
        boolean on = wifi != null && wifi.isWifiEnabled();
        String ssid = null;
        try {
            if (on && wifi.getConnectionInfo() != null) ssid = wifi.getConnectionInfo().getSSID();
        } catch (Exception ignored) {}
        if (ssid != null && (ssid.equals("<unknown ssid>") || ssid.equals("0x"))) ssid = null;
        status.setText(on
            ? ("Wi‑Fi: вкл" + (ssid != null ? (" · " + ssid) : ""))
            : "Wi‑Fi: выкл");
    }

    private void refreshList() {
        networks.clear();
        List<String> labels = new ArrayList<String>();
        List<ScanResult> raw;
        try {
            raw = wifi.getScanResults();
        } catch (SecurityException e) {
            adapter.clear();
            adapter.add("Нужно разрешение Location для скана (Android 6+)");
            adapter.notifyDataSetChanged();
            return;
        }
        if (raw == null) raw = Collections.emptyList();
        Map<String, ScanResult> best = new LinkedHashMap<String, ScanResult>();
        for (ScanResult r : raw) {
            if (r.SSID == null || r.SSID.length() == 0) continue;
            ScanResult prev = best.get(r.SSID);
            if (prev == null || prev.level < r.level) best.put(r.SSID, r);
        }
        List<ScanResult> uniq = new ArrayList<ScanResult>(best.values());
        Collections.sort(uniq, new Comparator<ScanResult>() {
            @Override public int compare(ScanResult a, ScanResult b) {
                return b.level - a.level;
            }
        });
        networks.addAll(uniq);
        for (ScanResult r : uniq) {
            boolean open = r.capabilities == null
                || !(r.capabilities.contains("WEP") || r.capabilities.contains("PSK") || r.capabilities.contains("EAP"));
            labels.add(String.format(Locale.US, "%s    %ddBm%s",
                r.SSID, r.level, open ? "  · open" : ""));
        }
        adapter.clear();
        if (labels.isEmpty()) adapter.add(wifi.isWifiEnabled() ? "Сетей нет — нажми «Сканировать»" : "Wi‑Fi выключен");
        else adapter.addAll(labels);
        adapter.notifyDataSetChanged();
        updateStatus();
    }

    private void connectDialog(final ScanResult r) {
        boolean open = r.capabilities == null
            || !(r.capabilities.contains("WEP") || r.capabilities.contains("PSK") || r.capabilities.contains("EAP"));
        if (open) {
            connect(r.SSID, null, false);
            return;
        }
        final EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        input.setHint("пароль");
        input.setTextColor(0xFF000000);
        new AlertDialog.Builder(this)
            .setTitle(r.SSID)
            .setView(input)
            .setPositiveButton("Подключить", new android.content.DialogInterface.OnClickListener() {
                @Override public void onClick(android.content.DialogInterface d, int w) {
                    connect(r.SSID, input.getText().toString(), true);
                }
            })
            .setNegativeButton("Отмена", null)
            .show();
    }

    @SuppressWarnings("deprecation")
    private void connect(String ssid, String pass, boolean secured) {
        WifiConfiguration conf = new WifiConfiguration();
        conf.SSID = "\"" + ssid + "\"";
        if (!secured) {
            conf.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE);
        } else {
            conf.preSharedKey = "\"" + pass + "\"";
        }
        int netId = wifi.addNetwork(conf);
        if (netId == -1) {
            // update existing
            List<WifiConfiguration> configured = wifi.getConfiguredNetworks();
            if (configured != null) {
                for (WifiConfiguration c : configured) {
                    if (c.SSID != null && c.SSID.equals("\"" + ssid + "\"")) {
                        netId = c.networkId;
                        if (secured) {
                            c.preSharedKey = "\"" + pass + "\"";
                            wifi.updateNetwork(c);
                        }
                        break;
                    }
                }
            }
        }
        if (netId == -1) {
            Toast.makeText(this, "Не удалось добавить сеть", Toast.LENGTH_LONG).show();
            return;
        }
        wifi.disconnect();
        boolean ok = wifi.enableNetwork(netId, true);
        wifi.reconnect();
        Toast.makeText(this, ok ? ("Подключаюсь к " + ssid + "…") : "enableNetwork failed", Toast.LENGTH_LONG).show();
        updateStatus();
    }
}
