rsync -av \
--include='*/' \
--include='run_summary.txt' \
--include='pluto.ini' \
--include='export/***' \
--exclude='*' \
nkoba@trinity:/data2/nkoba/pluto/runs_rbhl32/ \
./runs_rbhl32/
