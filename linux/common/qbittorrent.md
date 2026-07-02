




sudo clamscan --bell --cross-fs=yes --move="/home/nbhirud/nb/clamscan_infected_nb" --heuristic-alerts=yes --recursive -i .  | tee clamscan.log


clamscan -i -r \"%F\"


clamscan --cross-fs=yes --move=\"/home/nbhirud/nb/clamav_quarantine/\" --heuristic-alerts=yes --recursive -i \"%F\"  | tee -a \"/home/nbhirud/nb/clamav_quarantine/clamscan.log\"


sudo clamscan --bell --cross-fs=yes --move="infected/" --heuristic-alerts=yes --recursive -i .  | tee infected.log