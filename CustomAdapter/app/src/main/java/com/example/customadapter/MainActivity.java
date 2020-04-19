package com.example.customadapter;

import androidx.appcompat.app.AppCompatActivity;

import android.os.Bundle;
import android.widget.ListView;

public class MainActivity extends AppCompatActivity {

    ListView listview;
    String [] districts;
    int[] pics = {R.drawable._barisal,R.drawable._chandpur,R.drawable._cumilla,R.drawable._dhaka,R.drawable._feni,R.drawable._gazipur,
            R.drawable._habiganj,R.drawable._jessore,R.drawable._khulna,R.drawable._lokkhipur,R.drawable._mymensingh,R.drawable._noakhali,
            R.drawable._pabna};

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        districts = getResources().getStringArray(R.array.district);

        listview = findViewById(R.id.list_view);
        CustomAdapter adapter = new CustomAdapter(this,districts,pics);

        listview.setAdapter(adapter);

    }
}
