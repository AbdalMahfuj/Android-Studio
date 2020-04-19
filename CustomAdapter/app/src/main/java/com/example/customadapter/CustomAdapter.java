package com.example.customadapter;

import android.content.Context;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.BaseAdapter;
import android.widget.ImageView;
import android.widget.TextView;

public class CustomAdapter extends BaseAdapter {

    String[] districts;
    int[] pics;
    Context context;
    LayoutInflater inflater;

    CustomAdapter(Context context,String[] districts,int[] pics){  //constructor
        this.context=context;
        this.districts = districts;
        this.pics=pics;

    }

    @Override
    public int getCount() {
        return districts.length;
    }

    @Override
    public Object getItem(int position) {
        return null;
    }

    @Override
    public long getItemId(int position) {
        return 0;
    }

    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
        if(convertView==null) {
          inflater= (LayoutInflater) context.getSystemService(Context.LAYOUT_INFLATER_SERVICE);

            //convertView = LayoutInflater.from(context).inflate(R.layout.layout_list_view_row_items, parent, false);
            convertView = inflater.inflate(R.layout.sample_view,parent,false);

        }
        ImageView imageView = convertView.findViewById(R.id.image_view);
        TextView textview = convertView.findViewById(R.id.textview_up);

        imageView.setImageResource(pics[position]);
        textview.setText(districts[position]);

        return convertView;
    }
}
